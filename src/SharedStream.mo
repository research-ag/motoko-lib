import Debug "mo:base/Debug";
import Error "mo:base/Error";
import R "mo:base/Result";
import Time "mo:base/Time";
import Array "mo:base/Array";
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
    startIndex : Nat,
    timeoutSeconds : ?Nat,
    itemCallback : (item : T, index : Nat) -> (),
    // itemCallback is custom made per-stream and contains the streamId
  ) {

    var expectedNextIndex_ : Nat = startIndex;
    // rename to length_?
    var lastChunkReceived_ : Time.Time = Time.now();

    public func length() : Nat = expectedNextIndex_;

    let timeout : ?Nat = switch (timeoutSeconds) {
      case (?s) ?(s * 1_000_000_000);
      case (null) null;
    };

    /// returns timestamp when stream received last chunk
    public func lastChunkReceived() : Time.Time = lastChunkReceived_;

    /// returns flag is receiver closed stream with timeout
    public func isClosed() : Bool = switch (timeout) {
      case (?to)(Time.now() - lastChunkReceived_) > to;
      case (null) false;
    };

    /// a function, should be called by shared function or stream manager
    // This function is async* so that can throw an Error.
    // It does not make any subsequent calls.
    public func onChunk(chunk : [T], firstIndex : Nat) : async* Bool {
      if (firstIndex != expectedNextIndex_) {
        throw Error.reject("Broken pipe in StreamReceiver");
      };
      if (isClosed()) return false;
      lastChunkReceived_ := Time.now();
      var startIndex = firstIndex;
      for (i in chunk.keys()) {
        itemCallback(chunk[i], startIndex + i);
      };
      expectedNextIndex_ := startIndex + chunk.size();
      return true;
    };

    // should be used only in internal streams
    public func insertItem(item : T) : Nat {
      itemCallback(item, expectedNextIndex_);
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
  public class StreamSender<T, S>(
    maxQueueSize : ?Nat,
    counter : { accept(item : T) : Bool; reset() : () },
    wrapItem : T -> S,
    maxConcurrentChunks : Nat,
    keepAliveSeconds : Nat,
    sendFunc : (items : [S], firstIndex : Nat) -> async* Bool,
    // TODO Did we already change this to async* in deployment?
  ) {
    var closed : Bool = false;
    let queue = object {
      public let buf = SWB.SlidingWindowBuffer<T>();
      var head_ : Nat = 0;
      public func head() : Nat = head_;

      func pop() : T {
        let ?x = buf.getOpt(head_) else Debug.trap("queue empty in pop()");
        head_ += 1;
        x;
      };

      public func rewind() { head_ := buf.start() };
      public func size() : Nat { buf.end() - head_ : Nat };
      public func chunk() : (Nat, Nat, [S]) {
        var start = head_;
        var end = start;
        counter.reset();
        label peekLoop while (true) {
          switch (buf.getOpt(end)) {
            case (null) break peekLoop;
            case (?item) {
              if (not counter.accept(item)) break peekLoop;
              end += 1;
            };
          };
        };
        let elements = Array.tabulate<S>(end - start, func(n) = wrapItem(pop()));
        (start, end, elements);
      };
    };

    /// total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item
    public func length() : Nat = queue.buf.end();
    /// amount of items, which were sent to receiver
    public func sent() : Nat = queue.head();
    /// amount of items, successfully sent and acknowledged by receiver
    public func received() : Nat = queue.buf.start();

    /// get item from queue by index
    public func get(index : Nat) : ?T = queue.buf.getOpt(index);

    /// check busy status of sender
    public func isBusy() : Bool = window.isBusy();

    /// returns flag is receiver closed the stream
    public func isClosed() : Bool = closed;

    /// check paused status of sender
    public func isPaused() : Bool = window.hasError();

    /// update max amount of concurrent outgoing requests
    public func setMaxConcurrentChunks(value : Nat) = window.maxSize := value;

    var keepAliveInterval : Nat = keepAliveSeconds * 1_000_000_000;
    /// update max interval between stream calls
    public func setKeepAlive(seconds : Nat) {
      keepAliveInterval := seconds * 1_000_000_000;
    };

    /// add item to the stream
    public func add(item : T) : { #ok : Nat; #err : { #NoSpace } } {
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
      let (start, end, elements) = queue.chunk();
      if (nothingToSend(start, end)) return;
      window.send();
      try {
        switch (await* sendFunc(elements, start)) {
          case (true) window.receive(#ok(end));
          case (false) {
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
