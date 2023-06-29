# SharedStream

## Type `ChunkError`
``` motoko
type ChunkError = {#BrokenPipe : (expectedIndex : Nat, receivedIndex : Nat); #StreamClosed : Nat}
```


## Type `ResponseError`
``` motoko
type ResponseError = ChunkError or {#NotRegistered}
```


## Class `StreamReceiver<T>`

``` motoko
class StreamReceiver<T>(streamId : Nat, startFromIndex : Nat, closeStreamTimeoutSeconds : Nat, itemCallback : (streamId : Nat, item : T, index : Nat) -> (), chunkErrorCallback : (expectedIndex : Nat, receivedIndex : Nat) -> ())
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
class StreamSender<T>(streamId : Nat, maxQueueSize : ?Nat, weightLimit : Nat, weightFunc : (item : T) -> Nat, maxConcurrentChunks : Nat, sendFunc : (streamId : Nat, items : [T], firstIndex : Nat) -> async R.Result<(), ResponseError>)
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


### Function `next`
``` motoko
func next(item : T) : {#ok : Nat; #err : {#NoSpace}}
```

add item to the stream


### Function `sendChunk`
``` motoko
func sendChunk() : async* {#ok : Nat; #err : ChunkError or {#Paused; #Busy; #SendChunkError : Text}}
```

send chunk to the receiver

## Type `StreamSource`
``` motoko
type StreamSource = {#canister : Principal; #internal}
```


## Type `StreamInfo`
``` motoko
type StreamInfo<T> = { source : StreamSource; var nextItemId : Nat; var receiver : ?StreamReceiver<T> }
```


## Type `ManagerStableData`
``` motoko
type ManagerStableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, ?Nat>)
```


## Function `defaultManagerStableData`
``` motoko
func defaultManagerStableData() : ManagerStableData
```


## Class `StreamsManager<T>`

``` motoko
class StreamsManager<T>(initialSourceCanisters : [Principal], itemCallback : (streamId : Nat, item : T, index : Nat) -> Any)
```


### Function `sourceCanisters`
``` motoko
func sourceCanisters() : Vec.Vector<Principal>
```

principals of registered cross-canister stream sources


### Function `getStream`
``` motoko
func getStream(id : Nat) : ?StreamInfo<T>
```

get stream info by id


### Function `getNextStreamId`
``` motoko
func getNextStreamId() : Nat
```

get id, which will be assigned to next registered stream


### Function `sourceCanisterPrincipal`
``` motoko
func sourceCanisterPrincipal(streamId : Nat) : ?Principal
```

get principal of stream source by stream id


### Function `issueStreamId`
``` motoko
func issueStreamId(source : StreamSource) : R.Result<Nat, {#NotRegistered}>
```

register new stream


### Function `issueInternalStreamId`
``` motoko
func issueInternalStreamId() : Nat
```

register new internal stream


### Function `registerSourceCanister`
``` motoko
func registerSourceCanister(p : Principal) : ()
```

register new cross-canister stream


### Function `processBatch`
``` motoko
func processBatch(source : Principal, streamId : Nat, batch : [T], firstIndex : Nat) : R.Result<(), ResponseError>
```

handle chunk from incoming request


### Function `pushInternalItem`
``` motoko
func pushInternalItem(streamId : Nat, item : T) : (Nat, Nat)
```

append item to internal stream


### Function `share`
``` motoko
func share() : ManagerStableData
```



### Function `unshare`
``` motoko
func unshare(d : ManagerStableData)
```

