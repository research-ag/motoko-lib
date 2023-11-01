# PromTracker

## Type `StableData`
``` motoko
type StableData = AssocList.AssocList<Text, StableDataItem>
```


## Type `PullValueRef`
``` motoko
type PullValueRef = ValueRefMixin
```

A reference to pull value

## Type `AccumulatorValueRef`
``` motoko
type AccumulatorValueRef = ValueRefMixin and { set : (x : Nat) -> (); add : (x : Nat) -> () }
```

A reference to accumulator value

## Type `GaugeValueRef`
``` motoko
type GaugeValueRef = ValueRefMixin and { update : (x : Nat) -> () }
```

A reference to gauge value

## Class `PromTracker`

``` motoko
class PromTracker(watermarkResetIntervalSeconds : Nat)
```

Value tracker, designed specifically to use as source for Prometheus.

Example:
```motoko
let tracker = PromTracker.PromTracker(65); // 65 seconds is the recommended interval if prometheus pulls stats with interval 60 seconds
....
let successfulHeartbeats = tracker.addCounter("successful_heartbeats", true);
let failedHeartbeats = tracker.addCounter("failed_heartbeats", true);
let heartbeats = tracker.addPullValue("heartbeats", func() = successfulHeartbeats.value() + failedHeartbeats.value());
let heartbeatDuration = tracker.addGauge("heartbeat_duration", true);
....
// update values from your code
successfulHeartbeats.add(2);
failedHeartbeats.add(1);
heartbeatDuration.update(10);
heartbeatDuration.update(18);
heartbeatDuration.update(14);
....
// get prometheus metrics:
let text = tracker.renderStats();
```

Expected output is:
```
successful_heartbeats{} 2 1698842860811
failed_heartbeats{} 1 1698842860811
heartbeats{} 3 1698842860811
heartbeat_duration_sum{} 42 1698842860811
heartbeat_duration_count{} 3 1698842860811
heartbeat_duration_high_watermark{} 18 1698842860811
heartbeat_duration_low_watermark{} 10 1698842860811
```

### Function `addPullValue`
``` motoko
func addPullValue(prefix : Text, pull : () -> Nat) : PullValueRef
```

Add a stateless value, which outputs value, returned by provided `pull` function on demand

Example:
```motoko
let storageSize = tracker.addPullValue("storage_size", func() = storage.size());
```


### Function `addCounter`
``` motoko
func addCounter(prefix : Text, isStable : Bool) : AccumulatorValueRef
```

Add an accumulating counter

Example:
```motoko
let requestsAmount = tracker.addCounter("requests_amount", true);
....
requestsAmount.add(3);
requestsAmount.add(1);
```


### Function `addGauge`
``` motoko
func addGauge(prefix : Text, isStable : Bool) : GaugeValueRef
```

Add a gauge value for ever changing value, with ability to catch the highest and lowest value during interval, set on tracker instance.
outputs stats: sum of all pushed values, amount of pushes, lowest value during interval, highest value during interval

Example:
```motoko
let requestDuration = tracker.addGauge("request_duration", true);
....
requestDuration.update(123);
requestDuration.update(101);
```


### Function `addSystemValues`
``` motoko
func addSystemValues()
```

Add system metrics, such as cycle balance, memory size, heap size etc.


### Function `dump`
``` motoko
func dump() : [(Text, Nat)]
```

Dump all current stats to array


### Function `renderStats`
``` motoko
func renderStats() : Text
```

Render all current stats to prometheus format


### Function `share`
``` motoko
func share() : StableData
```

Dump all values, marked as stable, to stable data structure


### Function `unshare`
``` motoko
func unshare(data : StableData) : ()
```

Patch all values with stable data
