import Iter "mo:base/Iter";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";

module {

  type List<T> = ?{ e : T; var next : List<T> };

  // reference implementation, not tested
  class TemporaryQueueImpl<T>() {
    var list : List<T> = null;

    var histCnt_ : Nat = 0;
    var headCnt_ : Nat = 0;
    var tailCnt_ : Nat = 0;

    var hist : List<T> = null;
    var head : List<T> = null;
    var tail : List<T> = null;

    public func histId() : Nat = histCnt_;
    public func headId() : Nat = headCnt_;
    public func tailId() : Nat = tailCnt_;

    public func size() : Nat = tailCnt_ - headCnt_;
    public func historySize() : Nat = headCnt_ - histCnt_;
    public func fullSize() : Nat = tailCnt_ - histCnt_;

    public func push(element : T) {
      let oldTail = tail;
      tail := ?{ e = element; var next = null };
      switch (oldTail) {
        case (?t) t.next := tail;
        case (null) {
          head := tail;
          hist := tail;
        };
      };
      tailCnt_ += 1;
    };

    public func pop() : ?T {
      switch (head) {
        case (?h) {
          head := h.next;
          switch (head) {
            case (null) tail := null;
            case (_) {};
          };
          headCnt_ += 1;
          ?h.e;
        };
        case (null) { null };
      };
    };

    public func peek() : ?T {
      switch (head) {
        case (?h) ?h.e;
        case (null) null;
      };
    };

    public func restore() {
      head := hist;
      headCnt_ := histCnt_;
    };

    // prune history to provided id exclusively
    public func pruneHist(upToId : Nat) {
      if (upToId > headCnt_) {
        Debug.trap("Trying to prune main queue part");
      };
      var counter = upToId;
      var newHist = hist;
      for (i in Iter.range(0, upToId - histCnt_)) {
        switch (newHist) {
          case (?h) newHist := h.next;
          case (null) Debug.trap("Can never happen, newHist is null");
        };
      };
      hist := newHist;
      histCnt_ := upToId;
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
  class StreamReceiver<T>(
    streamId : Nat,
    callback : (streamId : Nat, item : T, index : Nat) -> (),
  ) {

    var expectedNextIndex_ : Nat = 0;

    public func onChunk(chunk : [T], firstIndex : Nat) : async () {
      if (firstIndex != expectedNextIndex_) {
        throw Error.reject("Broken chunk index: " # Nat.toText(firstIndex) # "; expected: " # Nat.toText(expectedNextIndex_));
      };
      for (index in chunk.keys()) {
        callback(streamId, chunk[index], firstIndex + index);
      };
      expectedNextIndex_ += chunk.size();
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
  /// sender.next([1, 2, 3, 4]);
  /// sender.next([5, 6, 7, 8]);
  /// sender.next([9, 10, 11, 12]);
  /// await* sender.sendChunk(); // will send (123, [1..10], 0) to `anotherCanister`
  /// await* sender.sendChunk(); // will send (123, [11..12], 10) to `anotherCanister`
  /// await* sender.sendChunk(); // will do nothing, stream clean
  class StreamSender<T>(
    streamId : Nat,
    maxSize : ?Nat,
    weightLimit : Nat,
    weightFunc : (item : T) -> Nat,
    callback : (streamId : Nat, items : [T], firstIndex : Nat) -> async (),
  ) {

    let queue : TemporaryQueueImpl<T> = TemporaryQueueImpl<T>();
    // a head of queue before submitting lately failed chunk. Used for error-handling
    var lowestError : { #Inf; #Val : Nat } = #Inf;

    public func next(items : [T]) : { #ok : Nat; #err : { #NoSpace } } {
      let finalSize = queue.size() + items.size();
      switch (maxSize) {
        case (?max) if (finalSize > max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      for (item in items.vals()) {
        queue.push(item);
      };
      #ok(finalSize);
    };

    public func sendChunk() : async* {
      #ok : Nat;
      #err : { #Paused; #SubscribtionError : Text };
    } {
      switch (lowestError) {
        case (#Inf) {};
        case (#Val _) { return #err(#Paused) };
      };
      let headId = queue.headId();
      streamIter.reset();
      let elements = Iter.toArray(streamIter);
      if (elements.size() == 0) {
        return #ok(0);
      };
      try {
        await callback(streamId, elements, headId);
        queue.pruneHist(headId + elements.size());
        #ok(elements.size());
      } catch (err : Error) {
        let lowestErr = switch (lowestError) {
          case (#Inf) headId;
          case (#Val val) Nat.min(val, headId);
        };
        lowestError := #Val(lowestErr);
        if (lowestErr < queue.histId()) { Debug.trap("cannot happen") };
        if (lowestErr == queue.histId()) {
          queue.restore();
          lowestError := #Inf;
        };
        #err(#SubscribtionError(Error.message(err)));
      };
    };

    class StreamIter<T>(queue : TemporaryQueueImpl<T>, weightFunc : (item : T) -> Nat) {
      var remainingWeight = 0;
      public func reset() : () {
        remainingWeight := weightLimit;
      };
      public func next() : ?T {
        if (remainingWeight == 0) { return null };
        switch (queue.peek()) {
          case (?el) {
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
