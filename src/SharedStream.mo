import Iter "mo:base/Iter";
import Error "mo:base/Error";

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

    public func headId() : Nat = headCnt_;

    public func size() : Nat = tailCnt_ - headCnt_;
    public func historySize() : Nat = headCnt_ - histCnt_;
    public func fullSize() : Nat = headCnt_ - histCnt_;

    public func push(elements : [T]) {
      for (el in elements.vals()) {
        let oldTail = tail;
        tail := ?{ e = el; var next = null };
        switch (oldTail) {
          case (?t) t.next := tail;
          case (null) {
            head := tail;
            hist := tail;
          };
        };
      };
      tailCnt_ += elements.size();
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

    public func pruneHist() {
      hist := head;
      histCnt_ := headCnt_;
    };

  };

  public type StreamSub<T> = ([T], Nat) -> async ();


  /// usage:
  /// let stream = SharedStream<Int>(10, 10, func (item) = 1);
  /// stream.next([1, 2, 3, 4]);
  /// stream.next([5, 6, 7, 8]);
  /// stream.next([9, 10, 11, 12]);
  /// stream.subscribe(func (elements: [Int]): async () {
  ///   await anotherCanister.appendStream(elements); 
  /// });
  /// await* stream.emit(); // will send items 1..9 to `anotherCanister`
  /// await* stream.emit(); // will send items 10..12 to `anotherCanister`
  /// await* stream.emit(); // will do nothing, stream clear
  class SharedStream<T>(
    maxSize : Nat,
    weightLimit : Nat,
    weightFunc : (item : T) -> Nat,
  ) {

    let queue : TemporaryQueueImpl<T> = TemporaryQueueImpl<T>();
    var subscribers : List<StreamSub<T>> = null;

    public func subscribe(callback : StreamSub<T>) {
      subscribers := ?{ e = callback; var next = subscribers };
    };

    public func unsubscribe(callback : StreamSub<T>) {
      // stub
    };

    public func next(items : [T]): { #ok : Nat; #err : { #NoSpace } } {
      let finalSize = queue.size() + items.size();
      if (finalSize > maxSize) {
        return #err(#NoSpace);
      };
      queue.push(items);
      #ok(finalSize);
    };

    public func emit() : async* { #ok : Nat; #err : { #HistoryDirty; #SubscribtionError: Text } } {
      if (queue.historySize() > 0) {
        return #err(#HistoryDirty);
      };
      let headId = queue.headId();
      streamIter.reset();
      let elements = Iter.toArray(streamIter);
      if (elements.size() == 0) {
        return #ok(0);
      };
      var subscription = subscribers;
      try {
        label l while (true) {
          switch (subscription) {
            case (?sub) {
              await sub.e(elements, headId);
              subscription := sub.next;
            };
            case (_) {
              break l;
            };
          };
        };
        queue.pruneHist();
        #ok(elements.size());
      } catch (err : Error) {
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
