import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";

import QueueBuffer "QueueBuffer";

module {

  public type ChunkError = {
    #BrokenPipe : Nat; // value is the expected first index in chunk
    #StreamClosed : Nat; // value is a stream length
  };

  public type ResponseError = ChunkError or { #NotRegistered };

  func require<T>(opt : ?T) : T {
    switch (opt) {
      case (?o) o;
      case (null) Debug.trap("Required value is null");
    };
  };

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
        return #err(#BrokenPipe(expectedNextIndex_));
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
    heartbeatIntervalSeconds : Nat,
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

    /// check busy status of sender
    public func isBusy() : Bool = concurrentChunksCounter >= maxConcurrentChunks_;

    /// check paused status of sender
    public func isPaused() : Bool = switch (lowestError) {
      case (null) false;
      case (?le) true;
    };

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

    var heartbeatInterval_ : Nat = heartbeatIntervalSeconds * 1_000_000_000;
    /// update max interval between stream calls
    public func setHeartbeatIntervalSeconds(value : Nat) {
      heartbeatInterval_ := value * 1_000_000_000;
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
    public func sendChunk() : async* () {
      if (isBusy()) Debug.trap("Stream sender is busy");
      switch (lowestError) {
        case (null) {};
        case (?le) Debug.trap("Stream sender is paused");
      };
      let headIndex = queue.headIndex();
      var remainingWeight = weightLimit_;
      var index = headIndex;
      label peekLoop while (true) {
        switch (queue.get(index)) {
          case (null) break peekLoop;
          case (?it) {
            let weight = weightFunc(it);
            if (remainingWeight < weight) {
              break peekLoop;
            } else {
              remainingWeight -= weight;
              index += 1;
            };
          };
        };
      };
      // skip sending if found 0 elements, unless sending keep-alive heartbeat call
      if (index == headIndex and (Time.now() - lastChunkTimestamp) < heartbeatInterval_) return;
      let elements = Array.tabulate<T>(index - headIndex, func(n) = require(queue.pop()).1);
      concurrentChunksCounter += 1;
      lastChunkTimestamp := Time.now();
      try {
        let resp = await sendFunc(streamId, elements, headIndex);
        concurrentChunksCounter -= 1;
        switch (resp) {
          case (#err err) switch (err) {
            case (#StreamClosed len) {
              queue.pruneTo(len);
              lowestError := ?len;
              rewindIfNeeded();
            };
            case (_) {};
          };
          case (#ok) {
            queue.pruneTo(index);
            rewindIfNeeded();
          };
        };
      } catch (err : Error) {
        concurrentChunksCounter -= 1;
        lowestError := ?(switch (lowestError) { case (null) headIndex; case (?val) Nat.min(val, headIndex) });
        rewindIfNeeded();
      };
    };

    private func rewindIfNeeded() {
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

  };

};
