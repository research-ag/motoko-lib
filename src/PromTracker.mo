import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Cycles "mo:base/ExperimentalCycles";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Prim "mo:prim";
import StableMemory "mo:base/ExperimentalStableMemory";
import Time "mo:base/Time";
import Text "mo:base/Text";

import Vector "mo:vector/Class";

module {

  type StableDataItem = { #counter : Nat; #gauge : (Nat, Nat) };
  public type StableData = AssocList.AssocList<Text, StableDataItem>;

  /// An access interface for pull value
  public type PullValueInterface = {
    value : () -> Nat;
    remove : () -> ();
  };
  /// An access interface for counter value
  public type CounterInterface = {
    value : () -> Nat;
    set : (x : Nat) -> ();
    add : (x : Nat) -> ();
    remove : () -> ();
  };
  /// An access interface for gauge value
  public type GaugeInterface = {
    value : () -> Nat;
    update : (x : Nat) -> ();
    remove : () -> ();
  };

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

    public var now : () -> Int = func() = Time.now();

    type IValue = {
      prefix : Text;
      dump : () -> [(Text, Nat)];
      share : () -> ?StableDataItem;
      unshare : (StableDataItem) -> ();
    };

    let values = Vector.Vector<?IValue>();

    /// Add a stateless value, which outputs value, returned by provided `pull` function on demand
    ///
    /// Example:
    /// ```motoko
    /// let storageSize = tracker.addPullValue("storage_size", func() = storage.size());
    /// ```
    public func addPullValue(prefix : Text, pull : () -> Nat) : PullValueInterface {
      let id = values.size();
      let value = PullValue(prefix, pull);
      values.add(?value);
      {
        value = pull;
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
    public func addCounter(prefix : Text, isStable : Bool) : CounterInterface {
      let id = values.size();
      let value = CounterValue(prefix, isStable);
      values.add(?value);
      {
        value = func() = value.value;
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
    public func addGauge(prefix : Text, buckets : ?[Nat], isStable : Bool) : GaugeInterface {
      let id = values.size();
      let value = GaugeValue(prefix, buckets, now, watermarkResetIntervalSeconds, isStable);
      values.add(?value);
      {
        value = func() = value.lastValue;
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

    func removeValue(id : Nat) : () = values.put(id, null);

    /// Dump all current stats to array
    public func dump() : [(Text, Nat)] {
      let result = Vector.Vector<(Text, Nat)>();
      for (v in values.vals()) {
        switch (v) {
          case (?value) Vector.addFromIter(result, Iter.fromArray(value.dump()));
          case (null) {};
        };
      };
      Vector.toArray(result);
    };

    func renderSingle(name : Text, value : Text, timestamp : Text) : Text = name # " " # value # " " # timestamp # "\n";

    /// Render all current stats to prometheus format
    public func renderExposition() : Text {
      let timestamp = Int.toText(now() / 1000000);
      var res = "";
      for ((name, value) in dump().vals()) {
        res #= renderSingle(name, Nat.toText(value), timestamp);
      };
      res;
    };

    /// Dump all values, marked as stable, to stable data structure
    public func share() : StableData {
      var res : StableData = null;
      for (value in values.vals()) {
        switch (value) {
          case (?v) switch (v.share()) {
            case (?data) {
              res := AssocList.replace(res, v.prefix, Text.equal, ?data).0;
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
      for (value in values.vals()) {
        switch (value) {
          case (?v) switch (AssocList.find(data, v.prefix, Text.equal)) {
            case (?data) v.unshare(data);
            case (_) {};
          };
          case (_) {};
        };
      };
    };

  };

  class PullValue(prefix_ : Text, pull : () -> Nat) {
    public let prefix = prefix_;

    public func dump() : [(Text, Nat)] = [(prefix # "{}", pull())];

    public func share() : ?StableDataItem = null;
    public func unshare(data : StableDataItem) = ();
  };

  class CounterValue(prefix_ : Text, isStable : Bool) {
    public let prefix = prefix_;

    public var value = 0;

    public func add(n : Nat) { value += n };
    public func set(n : Nat) { value := n };

    public func dump() : [(Text, Nat)] = [(prefix # "{}", value)];

    public func share() : ?StableDataItem {
      if (not isStable) return null;
      ? #counter(value);
    };
    public func unshare(data : StableDataItem) = switch (data, isStable) {
      case (#counter x, true) value := x;
      case (_) {};
    };
  };

  class GaugeValue(prefix_ : Text, buckets_ : ?[Nat], now : () -> Int, watermarkResetIntervalSeconds : Nat, isStable : Bool) {
    public let prefix = prefix_;
    public let buckets : ?[Nat] = switch (buckets_) {
      case (null) null;
      case (?b) ?Array.sort(b, Nat.compare);
    };

    class WatermarkTracker<T>(default : T, condition : (old : T, new : T) -> Bool, resetIntervalSeconds : Nat) {
      var lastWatermarkTimestamp : Time.Time = 0;
      public var value : T = default;
      public func update(current : T) {
        if (condition(value, current) or now() > lastWatermarkTimestamp + resetIntervalSeconds * 1_000_000_000) {
          value := current;
          lastWatermarkTimestamp := now();
        };
      };
    };

    public var count : Nat = 0;
    public var sum : Nat = 0;
    public var highWatermark : WatermarkTracker<Nat> = WatermarkTracker<Nat>(0, func(old, new) = new > old, watermarkResetIntervalSeconds);
    public var lowWatermark : WatermarkTracker<Nat> = WatermarkTracker<Nat>(0, func(old, new) = new < old, watermarkResetIntervalSeconds);
    public var lastValue : Nat = 0;
    public let bucketValues : [var Nat] = Array.tabulateVar<Nat>(
      switch (buckets) { case (?b) { b.size() + 1 }; case (null) { 0 } },
      func(n) = 0,
    );

    public func update(current : Nat) {
      count += 1;
      sum += current;
      highWatermark.update(current);
      lowWatermark.update(current);
      switch (buckets) {
        case (null) {};
        case (?b) {
          var skip : Nat = 0;
          label l for (bucketValue in b.vals()) {
            if (current <= bucketValue) {
              break l;
            } else {
              skip += 1;
            };
          };
          for (i in Iter.range(skip, bucketValues.size() - 1)) {
            bucketValues[i] += 1;
          };
        };
      };
    };

    public func dump() : [(Text, Nat)] = Array.tabulate<(Text, Nat)>(
      4 + bucketValues.size(),
      func(n) = switch (n) {
        case (0)(prefix # "_sum{}", sum);
        case (1)(prefix # "_count{}", count);
        case (2)(prefix # "_high_watermark{}", highWatermark.value);
        case (3)(prefix # "_low_watermark{}", lowWatermark.value);
        case (_)(
          prefix
          # "_bucket{le=\""
          # (if (n < bucketValues.size() + 3) { Nat.toText(Option.get(buckets, [])[n - 4]) } else { "+Inf" })
          # "\"}",
          bucketValues[n - 4],
        );
      },
    );

    public func share() : ?StableDataItem {
      if (not isStable) return null;
      ? #gauge(count, sum);
    };
    public func unshare(data : StableDataItem) = switch (data, isStable) {
      case (#gauge(c, s), true) {
        count := c;
        sum := s;
      };
      case (_) {};
    };
  };

};
