import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import R "mo:base/Result";
import Time "mo:base/Time";

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
};
