import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import Time "mo:base/Time";
import AssocList "mo:base/AssocList";
import List "mo:base/List";

import Vec "mo:vector";
import QueueBuffer "QueueBuffer";

module {

  public type ChunkError = {
    #BrokenPipe : (expectedIndex : Nat, receivedIndex : Nat);
    #StreamClosed : Nat; // key is a stream length
  };

  public type ResponseError = ChunkError or { #NotRegistered };

  /// Usage:
  ///
  /// let receiver = StreamReceiver<Int>(
  ///   123
  ///   func (streamId : Nat, element: Int, index: Nat): () {
  ///     ... do your logic with incoming item
  ///   }
  /// );
  ///
  /// Hook-up receive function in the actor class:
  /// public shared func onStreamChunk(streamId : Nat, chunk: [Int], firstIndex: Nat) : async () {
  ///   switch (streamId) case (123) { await receiver.onChunk(chunk, firstIndex); }; case (_) { Error.reject("Unknown stream"); }; };
  /// };
  public class StreamReceiver<T>(
    streamId : Nat,
    startFromIndex : Nat,
    closeStreamTimeoutSeconds : Nat,
    itemCallback : (streamId : Nat, item : T, index : Nat) -> (),
    chunkErrorCallback : (expectedIndex : Nat, receivedIndex : Nat) -> (),
  ) {

    var expectedNextIndex_ : Nat = startFromIndex;
    var lastChunkTimestamp : Time.Time = Time.now();

    let timeout = closeStreamTimeoutSeconds * 1_000_000_000;

    /// returns flag is receiver closed stream with timeout
    public func isStreamClosed() : Bool = (Time.now() - lastChunkTimestamp) > timeout;

    /// a function, should be called by shared function or stream manager
    public func onChunk(chunk : [T], firstIndex : Nat) : R.Result<(), ChunkError> {
      if (isStreamClosed()) {
        return #err(#StreamClosed(expectedNextIndex_));
      };
      if (firstIndex != expectedNextIndex_) {
        chunkErrorCallback(expectedNextIndex_, firstIndex);
        return #err(#BrokenPipe(expectedNextIndex_, firstIndex));
      };
      for (index in chunk.keys()) {
        itemCallback(streamId, chunk[index], firstIndex + index);
      };
      expectedNextIndex_ += chunk.size();
      #ok();
    };

  };

  /// Usage:
  ///
  /// let sender = StreamSender<Int>(
  ///   123,
  ///   10,
  ///   10,
  ///   func (item) = 1,
  ///   5,
  ///   anotherCanister.appendStream,
  /// );
  /// sender.next(1);
  /// sender.next(2);
  /// .....
  /// sender.next(12);
  /// await* sender.sendChunk(); // will send (123, [1..10], 0) to `anotherCanister`
  /// await* sender.sendChunk(); // will send (123, [11..12], 10) to `anotherCanister`
  /// await* sender.sendChunk(); // will do nothing, stream clean
  public class StreamSender<T>(
    streamId : Nat,
    maxQueueSize : ?Nat,
    weightLimit : Nat,
    weightFunc : (item : T) -> Nat,
    maxConcurrentChunks : Nat,
    sendFunc : (streamId : Nat, items : [T], firstIndex : Nat) -> async R.Result<(), ResponseError>,
  ) {
    let queue : QueueBuffer.QueueBuffer<T> = QueueBuffer.QueueBuffer<T>();
    // a head of queue before submitting lately failed chunk. Used for error-handling. Null behaves like infinity in calculations
    var lowestError : ?Nat = null;
    var lastChunkTimestamp : Time.Time = Time.now();

    /// full amount of items which weren't sent yet or sender waits for response from receiver
    public func fullAmount() : Nat = queue.fullSize();
    /// amount of scheduled items
    public func queuedAmount() : Nat = queue.queueSize();
    /// index, which will be assigned to next item
    public func nextIndex() : Nat = queue.nextIndex();
    /// get item from queue by index
    public func get(index : Nat) : ?T = queue.get(index);

    var weightLimit_ : Nat = weightLimit;
    /// update weight limit
    public func setWeightLimit(value : Nat) {
      weightLimit_ := value;
    };

    var maxConcurrentChunks_ : Nat = maxConcurrentChunks;
    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : Nat) {
      maxConcurrentChunks_ := value;
    };

    /// add item to the stream
    public func next(item : T) : { #ok : Nat; #err : { #NoSpace } } {
      switch (maxQueueSize) {
        case (?max) if (queue.queueSize() >= max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      #ok(queue.push(item));
    };

    var concurrentChunksCounter : Nat = 0;
    /// send chunk to the receiver
    public func sendChunk() : async* {
      #ok : Nat;
      #err : ChunkError or { #Paused; #Busy; #SendChunkError : Text };
    } {
      if (concurrentChunksCounter >= maxConcurrentChunks_) {
        return #err(#Busy);
      };
      switch (lowestError) {
        case (null) {};
        case (?le) { return #err(#Paused) };
      };
      let headId = queue.headIndex();
      streamIter.reset();
      let elements = Iter.toArray(streamIter);
      try {
        // if last call was more than 20 seconds ago, send anyway (keep-alive)
        if (elements.size() > 0 or (Time.now() - lastChunkTimestamp) > 20_000_000_000) {
          concurrentChunksCounter += 1;
          lastChunkTimestamp := Time.now();
          let resp = await sendFunc(streamId, elements, headId);
          concurrentChunksCounter -= 1;
          switch (resp) {
            case (#err err) switch (err) {
              case (#StreamClosed len) {
                queue.pruneTo(len);
                restoreHistoryIfNeeded();
                return #err(#StreamClosed(len));
              };
              case (#NotRegistered) return #err(#SendChunkError("Not registered"));
              case (#BrokenPipe _) return #err(#SendChunkError("Wrong index"));
            };
            case (#ok) {
              queue.pruneTo(headId + elements.size());
              restoreHistoryIfNeeded();
            };
          };
        };
        #ok(elements.size());
      } catch (err : Error) {
        concurrentChunksCounter -= 1;
        lowestError := ?(switch (lowestError) { case (null) headId; case (?val) Nat.min(val, headId) });
        restoreHistoryIfNeeded();
        #err(#SendChunkError(Error.message(err)));
      };
    };

    private func restoreHistoryIfNeeded() {
      switch (lowestError) {
        case (null) {};
        case (?val) {
          if (val < queue.rewindIndex()) { Debug.trap("cannot happen") };
          if (val == queue.rewindIndex()) {
            queue.rewind();
            lowestError := null;
          };
        };
      };
    };

    class StreamIter<T>(queue : QueueBuffer.QueueBuffer<T>, weightFunc : (item : T) -> Nat) {
      var remainingWeight = 0;
      public func reset() : () {
        remainingWeight := weightLimit_;
      };
      public func next() : ?T {
        if (remainingWeight == 0) { return null };
        switch (queue.peek()) {
          case (?(_, el)) {
            let weight = weightFunc(el);
            if (remainingWeight < weight) {
              return null;
            } else {
              ignore queue.pop();
              remainingWeight -= weight;
              return ?el;
            };
          };
          case _ {} // queue was empty: stop iteration
        };
        return null;
      };
    };
    let streamIter = StreamIter<T>(queue, weightFunc);
  };

  public type StreamSource = { #canister : Principal; #internal };

  public type StreamInfo<T> = {
    source : StreamSource;
    var nextItemId : Nat;
    var receiver : ?StreamReceiver<T>;
  };

  type StableStreamInfo = {
    source : StreamSource;
    nextItemId : Nat;
    active : Bool;
  };

  public type ManagerStableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, ?Nat>);
  public func defaultManagerStableData() : ManagerStableData = (Vec.new(), null);

  func requireOk<T>(res : R.Result<T, Any>) : T {
    switch (res) {
      case (#ok ok) ok;
      case (_) Debug.trap("Required result is #err");
    };
  };

  public class StreamsManager<T>(
    initialSourceCanisters : [Principal],
    itemCallback : (streamId : Nat, item : T, index : Nat) -> Any,
  ) {

    // info about each issued stream id is preserved here forever. Index is a stream ID
    let streams_ : Vec.Vector<StreamInfo<T>> = Vec.new();
    // a mapping of canister principal to stream id
    var sourceCanistersStreamMap : AssocList.AssocList<Principal, ?Nat> = null;

    /// principals of registered cross-canister stream sources
    public func sourceCanisters() : Vec.Vector<Principal> = Vec.fromIter(Iter.map<(Principal, ?Nat), Principal>(List.toIter(sourceCanistersStreamMap), func(p, n) = p));

    /// get stream info by id
    public func getStream(id : Nat) : ?StreamInfo<T> = Vec.getOpt(streams_, id);

    /// get id, which will be assigned to next registered stream
    public func getNextStreamId() : Nat = Vec.size(streams_);

    /// get principal of stream source by stream id
    public func sourceCanisterPrincipal(streamId : Nat) : ?Principal {
      switch (Vec.getOpt(streams_, streamId)) {
        case (null) null;
        case (?info) switch (info.source) {
          case (#canister p) ?p;
          case (_) null;
        };
      };
    };

    /// register new stream
    public func issueStreamId(source : StreamSource) : R.Result<Nat, { #NotRegistered }> {
      let id = Vec.size(streams_);
      switch (source) {
        case (#canister p) {
          let (map, oldValue) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, ??id);
          sourceCanistersStreamMap := map;
          switch (oldValue) {
            case (??sid) Vec.get(streams_, sid).receiver := null;
            case (_) {};
          };
        };
        case (#internal) {};
      };
      Vec.add(
        streams_,
        {
          source = source;
          var nextItemId = 0;
          var receiver = ?StreamReceiver<T>(id, 0, 120, streamItemCallback, chunkErrorCallback);
        },
      );
      #ok id;
    };

    func streamItemCallback(streamId : Nat, item : T, index : Nat) {
      let stream = Vec.get(streams_, streamId);
      stream.nextItemId += 1;
      ignore itemCallback(streamId, item, index);
    };

    func chunkErrorCallback(expectedIndex : Nat, receivedIndex : Nat) {
      Debug.trap("Broken chunk index: " # Nat.toText(receivedIndex) # "; expected: " # Nat.toText(expectedIndex));
    };

    /// register new internal stream
    public func issueInternalStreamId() : Nat = requireOk(issueStreamId(#internal));

    /// register new cross-canister stream
    public func registerSourceCanister(p : Principal) : () {
      switch (AssocList.find(sourceCanistersStreamMap, p, Principal.equal)) {
        case (?entry) {};
        case (_) {
          let (map, _) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, null);
          sourceCanistersStreamMap := map;
        };
      };
    };

    /// handle chunk from incoming request
    public func processBatch(source : Principal, streamId : Nat, batch : [T], firstIndex : Nat) : R.Result<(), ResponseError> {
      let stream = Vec.get(streams_, streamId);
      let callerOk = switch (stream.source) {
        case (#canister p) Principal.equal(source, p);
        case (#internal) false;
      };
      if (not callerOk) {
        return #err(#NotRegistered);
      };
      switch (stream.receiver) {
        case (?receiver) receiver.onChunk(batch, firstIndex);
        case (null) #err(#NotRegistered);
      };
    };

    /// append item to internal stream
    public func pushInternalItem(streamId : Nat, item : T) : (Nat, Nat) {
      let stream = Vec.get(streams_, streamId);
      switch (stream.source) {
        case (#canister p) Debug.trap("Cannot internally produce item in #canister stream");
        case (#internal) {};
      };
      switch (stream.receiver) {
        case (null) Debug.trap("Internal stream has to have an active receiver");
        case (?receiver) {
          let id = stream.nextItemId;
          requireOk(receiver.onChunk([item], id));
          (streamId, id);
        };
      };
    };

    public func share() : ManagerStableData {
      let streamsVec : Vec.Vector<StableStreamInfo> = Vec.new();
      for (info in Vec.vals(streams_)) {
        Vec.add(
          streamsVec,
          {
            source = info.source;
            nextItemId = info.nextItemId;
            active = switch (info.receiver) {
              case (?r) true;
              case (null) false;
            };
          },
        );
      };
      (streamsVec, sourceCanistersStreamMap);
    };

    public func unshare(d : ManagerStableData) {
      for ((info, id) in Vec.items(d.0)) {
        Vec.add(
          streams_,
          {
            source = info.source;
            var nextItemId = info.nextItemId;
            var receiver = switch (info.active) {
              case (true) ?StreamReceiver<T>(id, info.nextItemId, 120, streamItemCallback, chunkErrorCallback);
              case (false) null;
            };
          },
        );
      };
      sourceCanistersStreamMap := d.1;
    };
  };

};
