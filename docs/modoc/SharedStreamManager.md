# SharedStreamManager

## Type `StreamSource`
``` motoko
type StreamSource = {#canister : Principal; #internal}
```


## Type `StreamInfo`
``` motoko
type StreamInfo<T> = { source : StreamSource; var nextItemId : Nat; var receiver : ?SharedStream.StreamReceiver<T> }
```


## Type `StableData`
``` motoko
type StableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, ?Nat>)
```


## Function `defaultStableData`
``` motoko
func defaultStableData() : StableData
```


## Class `StreamsManager<T>`

``` motoko
class StreamsManager<T>(initialSourceCanisters : [Principal], itemCallback : (streamId : Nat, item : ?T, index : Nat) -> Any)
```

A manager, which is responsible for handling multiple incoming streams. Incapsulates a set of stream receivers

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


### Function `registerSourceCanister`
``` motoko
func registerSourceCanister(p : Principal) : ()
```

register new cross-canister stream


### Function `share`
``` motoko
func share(storeInternalStreams : Bool) : StableData
```



### Function `unshare`
``` motoko
func unshare(d : StableData)
```

