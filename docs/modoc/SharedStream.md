# SharedStream

## Type `ChunkError`
``` motoko
type ChunkError = {#BrokenPipe : Nat; #StreamClosed : Nat}
```


## Type `ResponseError`
``` motoko
type ResponseError = ChunkError or {#NotRegistered}
```


## Class `StreamReceiver<T>`

``` motoko
class StreamReceiver<T>(streamId : Nat, startFromIndex : Nat, closeStreamTimeoutSeconds : Nat, itemCallback : (streamId : Nat, item : T, index : Nat) -> ())
```

Usage:

let receiver = StreamReceiver<Int>(
  123
  func (streamId : Nat, element: Int, index: Nat): () {
    ... do your logic with incoming item
  }
);

Hook-up receive function in the actor class:
public shared func onStreamChunk(streamId : Nat, chunk: [Int], firstIndex: Nat) : async () {
  switch (streamId) case (123) { await receiver.onChunk(chunk, firstIndex); }; case (_) { Error.reject("Unknown stream"); }; };
};

### Function `isStreamClosed`
``` motoko
func isStreamClosed() : Bool
```

returns flag is receiver closed stream with timeout


### Function `onChunk`
``` motoko
func onChunk(chunk : [T], firstIndex : Nat) : R.Result<(), ChunkError>
```

a function, should be called by shared function or stream manager

## Class `StreamSender<T>`

``` motoko
class StreamSender<T>(streamId : Nat, maxQueueSize : ?Nat, weightLimit : Nat, weightFunc : (item : T) -> Nat, maxConcurrentChunks : Nat, heartbeatIntervalSeconds : Nat, sendFunc : (streamId : Nat, items : [T], firstIndex : Nat) -> async R.Result<(), ResponseError>)
```

Usage:

let sender = StreamSender<Int>(
  123,
  10,
  10,
  func (item) = 1,
  5,
  anotherCanister.appendStream,
);
sender.next(1);
sender.next(2);
.....
sender.next(12);
await* sender.sendChunk(); // will send (123, [1..10], 0) to `anotherCanister`
await* sender.sendChunk(); // will send (123, [11..12], 10) to `anotherCanister`
await* sender.sendChunk(); // will do nothing, stream clean

### Function `fullAmount`
``` motoko
func fullAmount() : Nat
```

full amount of items which weren't sent yet or sender waits for response from receiver


### Function `queuedAmount`
``` motoko
func queuedAmount() : Nat
```

amount of scheduled items


### Function `nextIndex`
``` motoko
func nextIndex() : Nat
```

index, which will be assigned to next item


### Function `get`
``` motoko
func get(index : Nat) : ?T
```

get item from queue by index


### Function `isBusy`
``` motoko
func isBusy() : Bool
```

check busy status of sender


### Function `isPaused`
``` motoko
func isPaused() : Bool
```

check paused status of sender


### Function `setWeightLimit`
``` motoko
func setWeightLimit(value : Nat)
```

update weight limit


### Function `setMaxConcurrentChunks`
``` motoko
func setMaxConcurrentChunks(value : Nat)
```

update max amount of concurrent outgoing requests


### Function `setHeartbeatIntervalSeconds`
``` motoko
func setHeartbeatIntervalSeconds(value : Nat)
```

update max interval between stream calls


### Function `next`
``` motoko
func next(item : T) : {#ok : Nat; #err : {#NoSpace}}
```

add item to the stream


### Function `sendChunk`
``` motoko
func sendChunk() : async* ()
```

send chunk to the receiver
