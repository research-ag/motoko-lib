# SharedStream

## Class `StreamReceiver<T>`

``` motoko
class StreamReceiver<T>(streamId : Nat, callback : (streamId : Nat, item : T, index : Nat) -> (), startFromIndex : Nat)
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



### Function `onChunk`
``` motoko
func onChunk(chunk : [T], firstIndex : Nat) : R.Result<(), {#StreamClosed}>
```


## Class `StreamSender<T>`

``` motoko
class StreamSender<T>(streamId : Nat, maxSize : ?Nat, weightLimit : Nat, weightFunc : (item : T) -> Nat, callback : (streamId : Nat, items : [T], firstIndex : Nat) -> async R.Result<(), StreamError>)
```

Usage:

let sender = StreamSender<Int>(
  123,
  10,
  10,
  func (item) = 1,
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



### Function `queuedAmount`
``` motoko
func queuedAmount() : Nat
```



### Function `nextIndex`
``` motoko
func nextIndex() : Nat
```



### Function `get`
``` motoko
func get(index : Nat) : ?T
```



### Function `next`
``` motoko
func next(item : T) : {#ok : Nat; #err : {#NoSpace}}
```



### Function `sendChunk`
``` motoko
func sendChunk() : async* {#ok : Nat; #err : {#Paused; #Busy; #SendChunkError : Text; #StreamClosed}}
```


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
type ManagerStableData = (Vec.Vector<StableStreamInfo>, Vec.Vector<(Principal, ?Nat)>)
```


## Function `defaultManagerStableData`
``` motoko
func defaultManagerStableData() : ManagerStableData
```


## Class `StreamsManager<T>`

``` motoko
class StreamsManager<T>(initialSourceCanisters : [Principal], itemCallback : (streamId : Nat, sourceCanisterIndex : ?Nat, item : T, index : Nat) -> Any)
```


### Function `sourceCanisters`
``` motoko
func sourceCanisters() : Vec.Vector<Principal>
```



### Function `getStream`
``` motoko
func getStream(id : Nat) : ?StreamInfo<T>
```



### Function `getNextStreamId`
``` motoko
func getNextStreamId() : Nat
```



### Function `issueStreamId`
``` motoko
func issueStreamId(source : StreamSource) : R.Result<Nat, {#NotRegistered}>
```



### Function `issueInternalStreamId`
``` motoko
func issueInternalStreamId() : Nat
```



### Function `registerSourceCanister`
``` motoko
func registerSourceCanister(p : Principal) : ()
```



### Function `sourceCanisterPrincipal`
``` motoko
func sourceCanisterPrincipal(streamId : Nat) : ?Principal
```



### Function `processBatch`
``` motoko
func processBatch(source : Principal, streamId : Nat, batch : [T], firstIndex : Nat) : R.Result<(), {#NotRegistered; #StreamClosed}>
```



### Function `pushInternalItem`
``` motoko
func pushInternalItem(streamId : Nat, item : T) : (Nat, Nat)
```



### Function `share`
``` motoko
func share() : ManagerStableData
```



### Function `unshare`
``` motoko
func unshare(d : ManagerStableData)
```

