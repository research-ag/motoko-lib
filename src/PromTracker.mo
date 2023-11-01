import AssocList "mo:base/AssocList";
import Cycles "mo:base/ExperimentalCycles";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Prim "mo:prim";
import StableMemory "mo:base/ExperimentalStableMemory";
import Time "mo:base/Time";
import Text "mo:base/Text";

import Vec "mo:vector";

module {

  type StableDataItem = { #counter : Nat; #gauge : (Nat, Nat) };
  public type StableData = AssocList.AssocList<Text, StableDataItem>;

  type ValueRefMixin = { value : () -> Nat; remove : () -> () };
  /// A reference to pull value
  public type PullValueRef = ValueRefMixin;
  /// A reference to accumulator value
  public type AccumulatorValueRef = ValueRefMixin and {
    set : (x : Nat) -> ();
    add : (x : Nat) -> ();
  };
  /// A reference to gauge value
  public type GaugeValueRef = ValueRefMixin and { update : (x : Nat) -> () };

  /// Value tracker, designed specifically to use as source for Prometheus.
  ///
  /// Example:
  /// ```motoko
  /// let tracker = PromTracker.PromTracker(65); // 65 seconds is the recommended interval if prometheus pulls stats with interval 60 seconds
  /// ....
  /// let successfulHeartbeats = tracker.addCounter("successful_heartbeats", true);
  /// let failedHeartbeats = tracker.addCounter("failed_heartbeats", true);
  /// let heartbeats = tracker.addPullValue("heartbeats", func() = successfulHeartbeats.value() + failedHeartbeats.value());
  /// let heartbeatDuration = tracker.addGauge("heartbeat_duration", true);
  /// ....
  /// // update values from your code
  /// successfulHeartbeats.add(2);
  /// failedHeartbeats.add(1);
  /// heartbeatDuration.update(10);
  /// heartbeatDuration.update(18);
  /// heartbeatDuration.update(14);
  /// ....
  /// // get prometheus metrics:
  /// let text = tracker.renderStats();
  /// ```
  ///
  /// Expected output is:
  /// ```
  /// successful_heartbeats{} 2 1698842860811
  /// failed_heartbeats{} 1 1698842860811
  /// heartbeats{} 3 1698842860811
  /// heartbeat_duration_sum{} 42 1698842860811
  /// heartbeat_duration_count{} 3 1698842860811
  /// heartbeat_duration_high_watermark{} 18 1698842860811
  /// heartbeat_duration_low_watermark{} 10 1698842860811
  /// ```
  public class PromTracker(watermarkResetIntervalSeconds : Nat) {

    type IValue = {
      dump : () -> [(Text, Nat)];
      prefix : () -> Text;
      share : () -> ?StableDataItem;
      unshare : (StableDataItem) -> ();
    };
    let values_ : Vec.Vector<?IValue> = Vec.new<?IValue>();

    func removeValue(id : Nat) : () = Vec.put(values_, id, null);

    /// Add a stateless value, which outputs value, returned by provided `pull` function on demand
    ///
    /// Example:
    /// ```motoko
    /// let storageSize = tracker.addPullValue("storage_size", func() = storage.size());
    /// ```
    public func addPullValue(prefix : Text, pull : () -> Nat) : PullValueRef {
      let id = Vec.size(values_);
      let value = PullValue(prefix, pull);
      Vec.add(values_, ?value);
      {
        value = value.value;
        remove = func() = removeValue(id);
      };
    };

    /// Add an accumulating counter
    ///
    /// Example:
    /// ```motoko
    /// let requestsAmount = tracker.addCounter("requests_amount", true);
    /// ....
    /// requestsAmount.add(3);
    /// requestsAmount.add(1);
    /// ```
    public func addCounter(prefix : Text, isStable : Bool) : AccumulatorValueRef {
      let id = Vec.size(values_);
      let value = AccumulatorValue(prefix, isStable);
      Vec.add(values_, ?value);
      {
        value = value.value;
        set = value.set;
        add = value.add;
        remove = func() = removeValue(id);
      };
    };

    /// Add a gauge value for ever changing value, with ability to catch the highest and lowest value during interval, set on tracker instance.
    /// outputs stats: sum of all pushed values, amount of pushes, lowest value during interval, highest value during interval
    ///
    /// Example:
    /// ```motoko
    /// let requestDuration = tracker.addGauge("request_duration", true);
    /// ....
    /// requestDuration.update(123);
    /// requestDuration.update(101);
    /// ```
    public func addGauge(prefix : Text, isStable : Bool) : GaugeValueRef {
      let id = Vec.size(values_);
      let value = GaugeValue(prefix, watermarkResetIntervalSeconds, isStable);
      Vec.add(values_, ?value);
      {
        value = value.lastValue;
        update = value.update;
        remove = func() = removeValue(id);
      };
    };

    /// Add system metrics, such as cycle balance, memory size, heap size etc.
    public func addSystemValues() {
      ignore addPullValue("cycles_balance", func() = Cycles.balance());
      ignore addPullValue("rts_memory_size", func() = Prim.rts_memory_size());
      ignore addPullValue("rts_heap_size", func() = Prim.rts_heap_size());
      ignore addPullValue("rts_total_allocation", func() = Prim.rts_total_allocation());
      ignore addPullValue("rts_reclaimed", func() = Prim.rts_reclaimed());
      ignore addPullValue("rts_max_live_size", func() = Prim.rts_max_live_size());
      ignore addPullValue("rts_max_stack_size", func() = Prim.rts_max_stack_size());
      ignore addPullValue("rts_callback_table_count", func() = Prim.rts_callback_table_count());
      ignore addPullValue("rts_callback_table_size", func() = Prim.rts_callback_table_size());
      ignore addPullValue("rts_mutator_instructions", func() = Prim.rts_mutator_instructions());
      ignore addPullValue("rts_collector_instructions", func() = Prim.rts_collector_instructions());
      ignore addPullValue("stablememory_size", func() = Nat64.toNat(StableMemory.size()));
    };

    /// Dump all current stats to array
    public func dump() : [(Text, Nat)] {
      let result : Vec.Vector<(Text, Nat)> = Vec.new();
      for (v in Vec.vals(values_)) {
        switch (v) {
          case (?value) Vec.addFromIter(result, Iter.fromArray(value.dump()));
          case (null) {};
        };
      };
      Vec.toArray(result);
    };

    func renderSingle(name : Text, value : Text, timestamp : Text) : Text = name # "{} " # value # " " # timestamp # "\n";

    /// Render all current stats to prometheus format
    public func renderStats() : Text {
      let timestamp = Int.toText(Time.now() / 1000000);
      var res = "";
      for ((name, value) in dump().vals()) {
        res #= renderSingle(name, Nat.toText(value), timestamp);
      };
      res;
    };

    /// Dump all values, marked as stable, to stable data structure
    public func share() : StableData {
      var res : StableData = null;
      for (value in Vec.vals(values_)) {
        switch (value) {
          case (?v) switch (v.share()) {
            case (?data) {
              res := AssocList.replace(res, v.prefix(), Text.equal, ?data).0;
            };
            case (_) {};
          };
          case (null) {};
        };
      };
      res;
    };

    /// Patch all values with stable data
    public func unshare(data : StableData) : () {
      for (value in Vec.vals(values_)) {
        switch (value) {
          case (?v) switch (AssocList.find(data, v.prefix(), Text.equal)) {
            case (?data) v.unshare(data);
            case (_) {};
          };
          case (_) {};
        };
      };
    };

  };

  class PullValue(prefix_ : Text, pull : () -> Nat) {

    public func value() : Nat = pull();

    public func dump() : [(Text, Nat)] = [(prefix_, pull())];

    public func prefix() : Text = prefix_;
    public func share() : ?StableDataItem = null;
    public func unshare(data : StableDataItem) = ();
  };

  class AccumulatorValue(prefix_ : Text, isStable : Bool) {
    var value_ = 0;

    public func value() : Nat = value_;
    public func add(n : Nat) { value_ += n };
    public func set(n : Nat) { value_ := n };

    public func dump() : [(Text, Nat)] = [(prefix_, value_)];

    public func prefix() : Text = prefix_;
    public func share() : ?StableDataItem {
      if (not isStable) return null;
      ? #counter(value_);
    };
    public func unshare(data : StableDataItem) = switch (data) {
      case (#counter x) value_ := x;
      case (_) {};
    };
  };

  class GaugeValue(prefix_ : Text, watermarkResetIntervalSeconds : Nat, isStable : Bool) {

    class WatermarkTracker<T>(default : T, condition : (old : T, new : T) -> Bool, resetIntervalSeconds : Nat) {
      var lastWatermarkTimestamp : Time.Time = 0;
      var val : T = default;
      public func value() : T = val;
      public func update(current : T) {
        if (condition(val, current)) {
          val := current;
          lastWatermarkTimestamp := Time.now();
        } else if (Time.now() > lastWatermarkTimestamp + resetIntervalSeconds * 1_000_000_000) {
          val := current;
        };
      };
    };

    var count_ : Nat = 0;
    var sum_ : Nat = 0;
    var highWatermark_ : WatermarkTracker<Nat> = WatermarkTracker<Nat>(0, func(old, new) = new > old, watermarkResetIntervalSeconds);
    var lowWatermark_ : WatermarkTracker<Nat> = WatermarkTracker<Nat>(0, func(old, new) = new < old, watermarkResetIntervalSeconds);
    var lastVal_ : Nat = 0;

    public func lastValue() : Nat = lastVal_;
    public func count() : Nat = count_;
    public func sum() : Nat = sum_;
    public func highWatermark() : Nat = highWatermark_.value();
    public func lowWatermark() : Nat = lowWatermark_.value();

    public func update(current : Nat) {
      count_ += 1;
      sum_ += current;
      highWatermark_.update(current);
      lowWatermark_.update(current);
    };

    public func dump() : [(Text, Nat)] = [
      (prefix_ # "_sum", sum()),
      (prefix_ # "_count", count()),
      (prefix_ # "_high_watermark", highWatermark()),
      (prefix_ # "_low_watermark", lowWatermark()),
    ];

    public func prefix() : Text = prefix_;
    public func share() : ?StableDataItem {
      if (not isStable) return null;
      ? #gauge(count_, sum_);
    };
    public func unshare(data : StableDataItem) = switch (data) {
      case (#gauge(c, s)) {
        count_ := c;
        sum_ := s;
      };
      case (_) {};
    };
  };

};
