# SharedStream

## Class `StreamReceiver<T>`

``` motoko
class StreamReceiver<T>(streamId : Nat, startFromIndex : Nat, closeStreamTimeoutSeconds : ?Nat, itemCallback : (streamId : Nat, item : ?T, index : Nat) -> ())
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

The function `onChunk` throws in case of a gap (= broken pipe). The
calling code should not catch the throw so that it gets passed through to
the enclosing async expression of the calling code.

### Function `lastChunkReceived`
``` motoko
func lastChunkReceived() : Time.Time
```

returns timestamp when stream received last chunk


### Function `length`
``` motoko
func length() : Nat
```

total amount of items, ever received


### Function `isStreamClosed`
``` motoko
func isStreamClosed() : Bool
```

returns flag is receiver closed stream with timeout


### Function `onChunk`
``` motoko
func onChunk(chunk : [T], firstIndex : Nat, skippedFirst : Bool) : async* R.Result<(), ()>
```

a function, should be called by shared function or stream manager


### Function `insertItem`
``` motoko
func insertItem(item : T) : Nat
```


## Class `StreamSender<T>`

``` motoko
class StreamSender<T>(streamId : Nat, maxQueueSize : ?Nat, weightLimit : Nat, weightFunc : (item : T) -> Nat, maxConcurrentChunks : Nat, keepAliveSeconds : Nat, sendFunc : (streamId : Nat, items : [T], firstIndex : Nat, skippedFirst : Bool) -> async* R.Result<(), ()>)
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

### Function `length`
``` motoko
func length() : Nat
```

total amount of items, ever added to the stream sender, also an index, which will be assigned to the next item


### Function `sent`
``` motoko
func sent() : Nat
```

amount of items, which were sent to receiver


### Function `received`
``` motoko
func received() : Nat
```

amount of items, successfully sent and acknowledged by receiver


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


### Function `isStreamClosed`
``` motoko
func isStreamClosed() : Bool
```

returns flag is receiver closed the stream


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


### Function `setKeepAlive`
``` motoko
func setKeepAlive(seconds : Nat)
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
