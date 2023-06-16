import Iter "mo:base/Iter";
import Error "mo:base/Error";
import Debug "mo:base/Debug";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import Int "mo:base/Int";

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
    public func nextId() : Nat = tailCnt_;

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

    public func get(index : Nat) : ?T {
      if (index < histCnt_) return null;
      var counter = Int.abs(index - histCnt_);
      var item : List<T> = hist;
      while (counter > 0) {
        switch (item) {
          case (?it) item := it.next;
          case (null) return null;
        };
        counter -= 1;
      };
      Option.map<{ e : T; var next : List<T> }, T>(item, func(it) = it.e);
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
  public class StreamReceiver<T>(
    streamId : Nat,
    callback : (streamId : Nat, item : T, index : Nat) -> (),
    startFromIndex : Nat,
  ) {

    var expectedNextIndex_ : Nat = startFromIndex;

    public func onChunk(chunk : [T], firstIndex : Nat) {
      if (firstIndex != expectedNextIndex_) {
        Debug.trap("Broken chunk index: " # Nat.toText(firstIndex) # "; expected: " # Nat.toText(expectedNextIndex_));
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
    callback : (streamId : Nat, items : [T], firstIndex : Nat) -> async (),
  ) {

    let queue : TemporaryQueueImpl<T> = TemporaryQueueImpl<T>();
    // a head of queue before submitting lately failed chunk. Used for error-handling
    var lowestError : { #Inf; #Val : Nat } = #Inf;

    public func fullAmount() : Nat = queue.fullSize();
    public func queuedAmount() : Nat = queue.size();
    public func nextId() : Nat = queue.nextId();

    public func get(index : Nat) : ?T = queue.get(index);

    public func next(item : T) : { #ok : Nat; #err : { #NoSpace } } {
      switch (maxSize) {
        case (?max) if (queue.size() >= max) {
          return #err(#NoSpace);
        };
        case (_) {};
      };
      let id = nextId();
      queue.push(item);
      #ok(id);
    };

    public func sendChunk() : async* {
      #ok : Nat;
      #err : { #Paused; #SendChunkError : Text };
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
        restoreHistoryIfNeeded();
        #ok(elements.size());
      } catch (err : Error) {
        lowestError := #Val(switch (lowestError) { case (#Inf) headId; case (#Val val) Nat.min(val, headId) });
        restoreHistoryIfNeeded();
        #err(#SendChunkError(Error.message(err)));
      };
    };

    private func restoreHistoryIfNeeded() {
      switch (lowestError) {
        case (#Inf) {};
        case (#Val val) {
          if (val < queue.histId()) { Debug.trap("cannot happen") };
          if (val == queue.histId()) {
            queue.restore();
            lowestError := #Inf;
          };
        };
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
