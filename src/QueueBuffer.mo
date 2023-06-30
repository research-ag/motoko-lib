// QueueBuffer
//
import Prim "mo:⛔";
import { bitcountLeadingZero = leadingZeros; fromNat = Nat32; toNat = Nat } "mo:base/Nat32";
import Array "mo:base/Array";
import SWB "mo:swb";

module {
  /// A queue with fast random access, which preserves history of popped values
  public class QueueBuffer<X>() {
    var buf = SWB.SlidingWindowBuffer<X>();
    var head : Nat = 0;

    /// get index of oldest item in queue history
    public func rewindIndex() : Nat = buf.offset();
    /// get index of oldest item in queue
    public func headIndex() : Nat = head;
    /// get next index which will be issued
    public func nextIndex() : Nat = buf.size();

    /// amount of items in the queue
    public func queueSize() : Nat = buf.size() - head;
    /// total amount of items in the queue and history
    public func fullSize() : Nat = buf.len();

    /// append item to queue tail
    public func push(x : X) : Nat = buf.add(x);
    /// pop item from queue head
    public func pop() : ?(Nat, X) = do ? {
      let ret = (head, buf.getOpt(head)!);
      head += 1;
      ret;
    };
    /// get item from queue head
    public func peek() : ?(Nat, X) = do ? {
      let ret = (head, buf.getOpt(head)!);
      ret;
    };
    /// get item by id
    public func get(index : Nat) : ?X = buf.getOpt(index);
    /// clear history
    public func pruneAll() {
      buf.delete(head - buf.offset());
    };
    /// clear history up to provided item id
    public func pruneTo(n : Nat) {
      buf.delete(n - buf.offset());
    };
    /// restore whole history in the queue
    public func rewind() {
      head := buf.offset();
    };
  };
};
