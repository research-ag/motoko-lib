import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Option "mo:base/Option";

import SWB "mo:swb";

module {

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
  ///
  /// The function `onChunk` throws in case of a gap (= broken pipe). The
  /// calling code should not catch the throw so that it gets passed through to
  /// the enclosing async expression of the calling code.
  public class StreamReceiver<T>(
    streamId : Nat,
    startFromIndex : Nat,
    closeStreamTimeoutSeconds : ?Nat,
    itemCallback : (streamId : Nat, item : ?T, index : Nat) -> (),
  ) {

    var expectedNextIndex_ : Nat = startFromIndex;
    var lastChunkReceived_ : Time.Time = Time.now();

    let timeout : ?Nat = switch (closeStreamTimeoutSeconds) {
      case (?s) ?(s * 1_000_000_000);
      case (null) null;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Time.Time = lastChunkReceived_;

    /// returns flag is receiver closed stream with timeout
    public func isStreamClosed() : Bool = switch (timeout) {
      case (?to) (Time.now() - lastChunkReceived_) > to;
      case (null) false;
    };

    /// a function, should be called by shared function or stream manager
    public func onChunk(chunk : [T], firstIndex : Nat, skippedFirst : Bool) : async* R.Result<(), ()> {
      if (firstIndex != expectedNextIndex_) {
        throw Error.reject("Broken pipe in StreamReceiver");
      };
      if (isStreamClosed()) {
        return #err;
      };
      lastChunkReceived_ := Time.now();
      var startIndex = firstIndex;
      if (skippedFirst) {
        itemCallback(streamId, null, firstIndex);
        startIndex += 1;
      };
      for (index in chunk.keys()) {
        itemCallback(streamId, ?chunk[index], startIndex + index);
      };
      expectedNextIndex_ := startIndex + chunk.size();
      #ok;
    };

    // should be used only in internal streams
    public func insertItem(item : T) : Nat {
      itemCallback(streamId, ?item, expectedNextIndex_);
      expectedNextIndex_ += 1;
      expectedNextIndex_ - 1;
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
    keepAliveSeconds : Nat,
    sendFunc : (streamId : Nat, items : [T], firstIndex : Nat, skippedFirst : Bool) -> async R.Result<(), ()>,
  ) {
    var closed : Bool = false;
    let queue = object {
      // TODO: We currently expose buf to save some public function definitions
      // We could introduce public pass-through functions if desired.
      public let buf = SWB.SlidingWindowBuffer<T>();
      var head : Nat = 0;
      let weight : T -> Nat = weightFunc;
      var limit : Nat = weightLimit;

      func pop() : T {
        let ?x = buf.getOpt(head) else Debug.trap("queue empty in pop()");
        head += 1;
        x;
      };

      public func rewind() { head := buf.start() };
      public func size() : Nat { buf.end() - head : Nat };
      public func chunk() : (Nat, Nat, [T], Bool) {
        var start = head;
        var sum = 0;
        var end = start;
        // if item has weight more than limit, we drop it. Works only on the first item in chunk
        var skippedFirst : Bool = false;
        label peekLoop while (true) {
          switch (buf.getOpt(end)) {
            case (null) break peekLoop;
            case (?it) {
              let w = weight(it);
              if (sum + w > limit) {
                if (end == start) {
                  // item has bigger weight than weight limit
                  skippedFirst := true;
                  ignore pop();
                } else {
                  break peekLoop;
                };
              } else {
                sum += w;
                end += 1;
              };
            };
          };
        };
        let elements = Array.tabulate<T>(end - start, func(n) = pop());
        (start, end, elements, skippedFirst);
      };
      public func setLimit(weightLimit : Nat) { limit := weightLimit };
    };

    /// full amount of items which weren't sent yet or sender waits for response from receiver
    public func fullAmount() : Nat = queue.buf.len();
    /// amount of scheduled items
    public func queuedAmount() : Nat = queue.size();
    /// index, which will be assigned to next item
    public func nextIndex() : Nat = queue.buf.end();
    /// get item from queue by index
    public func get(index : Nat) : ?T = queue.buf.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool = window.isBusy();

    /// returns flag is receiver closed the stream
    public func isStreamClosed() : Bool = closed;

    /// check paused status of sender
    public func isPaused() : Bool = window.hasError();

    /// update weight limit
    public func setWeightLimit(value : Nat) = queue.setLimit(value);

    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : Nat) = window.maxSize := value;

    var keepAliveInterval : Nat = keepAliveSeconds * 1_000_000_000;
    /// update max interval between stream calls
    public func setKeepAlive(seconds : Nat) {
      keepAliveInterval := seconds * 1_000_000_000;
    };

    /// add item to the stream
    public func next(item : T) : { #ok : Nat; #err : { #NoSpace } } {
      switch (maxQueueSize) {
        case (?max) if (queue.buf.len() >= max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      #ok(queue.buf.add(item));
    };

    // The receive window of the sliding window protocol
    let window = object {
      public var maxSize = maxConcurrentChunks;
      public var lastChunkSent = Time.now();
      var size = 0;
      var error_ = false;

      func isClosed() : Bool { size == 0 }; // if window is closed (not stream)
      public func hasError() : Bool { error_ };
      public func isBusy() : Bool { size == maxSize };
      public func send() {
        lastChunkSent := Time.now();
        size += 1;
      };
      public func receive(msg : { #ok : Nat; #err }) {
        switch (msg) {
          case (#ok(pos)) queue.buf.deleteTo(pos);
          case (#err) error_ := true;
        };
        size -= 1;
        if (isClosed() and error_) {
          queue.rewind();
          error_ := false;
        };
      };
    };

    func nothingToSend(start : Nat, end : Nat) : Bool {
      // skip sending empty chunk unless keep-alive is due
      start == end and Time.now() < window.lastChunkSent + keepAliveInterval
    };

    /// send chunk to the receiver
    public func sendChunk() : async* () {
      if (closed) Debug.trap("Stream closed");
      if (window.isBusy()) Debug.trap("Stream sender is busy");
      if (window.hasError()) Debug.trap("Stream sender is paused");
      let (start, end, elements, skippedFirst) = queue.chunk();
      if (nothingToSend(start, end)) return;
      window.send();
      try {
        switch (await sendFunc(streamId, elements, start, skippedFirst)) {
          case (#ok) window.receive(#ok(end));
          case (#err) {
            // This response came from the first batch after the stream's
            // closing position, hence `start` is exactly the final length of
            // the stream.
            window.receive(#ok(start));
            closed := true;
          };
        };
      } catch (e) {
        window.receive(#err);
        throw e;
      };
    };
  };
};
