import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import Time "mo:base/Time";
import Timer "mo:base/Timer";

import Vec "mo:vector";
import QueueBuffer "QueueBuffer";

module {

  type StreamError = { #NotRegistered; #StreamClosed };

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
    callback : (streamId : Nat, item : T, index : Nat) -> (),
    startFromIndex : Nat,
  ) {

    var expectedNextIndex_ : Nat = startFromIndex;

    var lastChunkTimestamp : Time.Time = Time.now();

    public func isStreamClosed() : Bool = (Time.now() - lastChunkTimestamp) > 120_000_000_000; // 2 minutes

    public func onChunk(chunk : [T], firstIndex : Nat) : R.Result<(), { #StreamClosed }> {
      if (isStreamClosed()) {
        return #err(#StreamClosed);
      };
      if (firstIndex != expectedNextIndex_) {
        Debug.trap("Broken chunk index: " # Nat.toText(firstIndex) # "; expected: " # Nat.toText(expectedNextIndex_));
      };
      for (index in chunk.keys()) {
        callback(streamId, chunk[index], firstIndex + index);
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
    maxSize : ?Nat,
    weightLimit : Nat,
    weightFunc : (item : T) -> Nat,
    callback : (streamId : Nat, items : [T], firstIndex : Nat) -> async R.Result<(), StreamError>,
  ) {

    let queue : QueueBuffer.QueueBuffer<T> = QueueBuffer.QueueBuffer<T>();
    // a head of queue before submitting lately failed chunk. Used for error-handling
    var lowestError : { #Inf; #Val : Nat } = #Inf;

    public func fullAmount() : Nat = queue.fullSize();
    public func queuedAmount() : Nat = queue.queueSize();
    public func nextIndex() : Nat = queue.nextIndex();

    public func get(index : Nat) : ?T = queue.get(index);

    var lastChunkTimestamp : Time.Time = Time.now();
    var heartbeatTimer : Nat = 0;
    heartbeatTimer := Timer.recurringTimer(
      #seconds 30,
      func() : async () {
        // if last call was more than 20 seconds ago, send empty chunk
        if ((Time.now() - lastChunkTimestamp) > 20_000_000_000) {
          try {
            switch (await callback(streamId, [], queue.headIndex())) {
              case (#ok) lastChunkTimestamp := Time.now();
              case (#err err) Timer.cancelTimer(heartbeatTimer);
            };
          } catch (err) {
            // pass
          };
        };
      },
    );

    public func next(item : T) : { #ok : Nat; #err : { #NoSpace } } {
      switch (maxSize) {
        case (?max) if (queue.queueSize() >= max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      #ok(queue.push(item));
    };

    var concurrentChunksCounter : Nat = 0;
    public func sendChunk() : async* {
      #ok : Nat;
      #err : { #Paused; #Busy; #SendChunkError : Text; #StreamClosed };
    } {
      if (concurrentChunksCounter >= 5) {
        return #err(#Busy);
      };
      switch (lowestError) {
        case (#Inf) {};
        case (#Val _) { return #err(#Paused) };
      };
      let headId = queue.headIndex();
      streamIter.reset();
      let elements = Iter.toArray(streamIter);
      if (elements.size() == 0) {
        return #ok(0);
      };
      try {
        concurrentChunksCounter += 1;
        let resp = await callback(streamId, elements, headId);
        concurrentChunksCounter -= 1;
        switch (resp) {
          case (#err err) {
            Timer.cancelTimer(heartbeatTimer);
            return #err(
              switch (err) {
                case (#StreamClosed) #StreamClosed;
                case (#NotRegistered) #SendChunkError("Not registered");
              }
            );
          };
          case (#ok) lastChunkTimestamp := Time.now();
        };
        queue.pruneTo(headId + elements.size());
        restoreHistoryIfNeeded();
        #ok(elements.size());
      } catch (err : Error) {
        concurrentChunksCounter -= 1;
        lowestError := #Val(switch (lowestError) { case (#Inf) headId; case (#Val val) Nat.min(val, headId) });
        restoreHistoryIfNeeded();
        #err(#SendChunkError(Error.message(err)));
      };
    };

    private func restoreHistoryIfNeeded() {
      switch (lowestError) {
        case (#Inf) {};
        case (#Val val) {
          if (val < queue.rewindIndex()) { Debug.trap("cannot happen") };
          if (val == queue.rewindIndex()) {
            queue.rewind();
            lowestError := #Inf;
          };
        };
      };
    };

    class StreamIter<T>(queue : QueueBuffer.QueueBuffer<T>, weightFunc : (item : T) -> Nat) {
      var remainingWeight = 0;
      public func reset() : () {
        remainingWeight := weightLimit;
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

  public type ManagerStableData = (Vec.Vector<StableStreamInfo>, Vec.Vector<(Principal, ?Nat)>);
  public func defaultManagerStableData() : ManagerStableData = (Vec.new(), Vec.new());

  func requireOk<T>(res : R.Result<T, Any>) : T {
    switch (res) {
      case (#ok ok) ok;
      case (_) Debug.trap("Required result is #err");
    };
  };

  public class StreamsManager<T>(
    initialSourceCanisters : [Principal],
    itemCallback : (streamId : Nat, sourceCanisterIndex : ?Nat, item : T, index : Nat) -> Any,
  ) {

    // info about each issued stream id is preserved here forever. Index is a stream ID
    let streams_ : Vec.Vector<StreamInfo<T>> = Vec.new();
    // a list of registered source canister principals
    let sourceCanisters_ : Vec.Vector<Principal> = Vec.fromArray(initialSourceCanisters);
    // a list of source canister current stream id-s, can be mapped to 'sourceCanisters' by indices
    let sourceCanisterStreamIds_ : Vec.Vector<?Nat> = Vec.init<?Nat>(initialSourceCanisters.size(), null);

    public func sourceCanisters() : Vec.Vector<Principal> = sourceCanisters_;

    public func getStream(id : Nat) : ?StreamInfo<T> = Vec.getOpt(streams_, id);

    public func getNextStreamId() : Nat = Vec.size(streams_);

    public func issueStreamId(source : StreamSource) : R.Result<Nat, { #NotRegistered }> {
      let id = Vec.size(streams_);
      switch (source) {
        case (#canister p) switch (Vec.indexOf(p, sourceCanisters_, Principal.equal)) {
          case (null) return #err(#NotRegistered);
          case (?srcIndex) {
            switch (Vec.get(sourceCanisterStreamIds_, srcIndex)) {
              case (?oldStreamId) Vec.get(streams_, oldStreamId).receiver := null;
              case (_) {};
            };
            Vec.put(sourceCanisterStreamIds_, srcIndex, ?id);
          };
        };
        case (#internal) {};
      };
      Vec.add(
        streams_,
        {
          source = source;
          var nextItemId = 0;
          var receiver = ?StreamReceiver<T>(id, streamCallback, 0);
        },
      );
      #ok id;
    };

    func streamCallback(streamId : Nat, item : T, index : Nat) {
      let stream = Vec.get(streams_, streamId);
      let sourceIndex : ?Nat = switch (stream.source) {
        case (#canister p) Vec.indexOf(p, sourceCanisters_, Principal.equal);
        case (_) null;
      };
      stream.nextItemId += 1;
      ignore itemCallback(streamId, sourceIndex, item, index);
    };

    public func issueInternalStreamId() : Nat = requireOk(issueStreamId(#internal));

    public func registerSourceCanister(p : Principal) : () {
      Vec.add(sourceCanisters_, p);
      Vec.add(sourceCanisterStreamIds_, null);
    };

    public func sourceCanisterPrincipal(streamId : Nat) : ?Principal {
      switch (Vec.getOpt(streams_, streamId)) {
        case (null) null;
        case (?info) switch (info.source) {
          case (#canister p) ?p;
          case (_) null;
        };
      };
    };

    // handle chunk from incoming request
    public func processBatch(source : Principal, streamId : Nat, batch : [T], firstIndex : Nat) : R.Result<(), { #NotRegistered; #StreamClosed }> {
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
      let vec : Vec.Vector<(Principal, ?Nat)> = Vec.new();
      for (i in Vec.keys(sourceCanisters_)) {
        Vec.add(vec, (Vec.get(sourceCanisters_, i), Vec.get(sourceCanisterStreamIds_, i)));
      };
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
      (streamsVec, vec);
    };

    public func unshare(d : ManagerStableData) {
      Vec.clear(streams_);
      Vec.clear(sourceCanisters_);
      Vec.clear(sourceCanisterStreamIds_);
      for ((info, id) in Vec.items(d.0)) {
        Vec.add(
          streams_,
          {
            source = info.source;
            var nextItemId = info.nextItemId;
            var receiver = switch (info.active) {
              case (true) ?StreamReceiver<T>(id, streamCallback, info.nextItemId);
              case (false) null;
            };
          },
        );
      };
      for ((p, id) in Vec.vals(d.1)) {
        Vec.add(sourceCanisters_, p);
        Vec.add(sourceCanisterStreamIds_, id);
      };
    };
  };

};
