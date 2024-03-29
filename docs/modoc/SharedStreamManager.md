# SharedStreamManager

## Type `StreamSource`
``` motoko
type StreamSource = {#canister : (slotIndex : Nat, source : Principal); #internal}
```


## Type `StreamInfo`
``` motoko
type StreamInfo<T> = { source : StreamSource; var length : Nat; var receiver : ?Receiver<T> }
```


## Type `StableData`
``` motoko
type StableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, [?Nat]>)
```


## Function `defaultStableData`
``` motoko
func defaultStableData() : StableData
```


## Type `Callbacks`
``` motoko
type Callbacks<T> = { onReceiverRegistered : (streamId : Nat, receiver : Receiver<T>, source : StreamSource) -> (); onReceiverDeregistered : (streamId : Nat, receiver : Receiver<T>, source : StreamSource) -> () }
```


## Class `StreamsManager<T>`

``` motoko
class StreamsManager<T>(streamsPerSourceCanister : Nat, itemCallback : (streamId : Nat, item : ?T, index : Nat) -> Bool, maxStreamLength : ?Nat)
```

A manager, which is responsible for handling multiple incoming streams. Incapsulates a set of stream receivers

### Function `sourceCanisters`
``` motoko
func sourceCanisters() : [Principal]
```

principals of registered cross-canister stream sources


### Function `prioritySourceCanisters`
``` motoko
func prioritySourceCanisters(streamSlot : Nat) : [(Principal, Nat)]
```

principals of cross-canister stream sources with the priority. The priority value tells the caller with what probability they should
chose that canister for their needs (sum of all values is not normalized). In the future this value will be used for
load balancing, for now it returns either 0 or 1. Zero value means that stream is closed and the canister should not be used


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


### Function `closeStreamIfOpened`
``` motoko
func closeStreamIfOpened(sid : Nat)
```

close stream by id. Do nothing if does not exist or already closed


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


### Function `deregisterSourceCanister`
``` motoko
func deregisterSourceCanister(p : Principal) : ()
```

deregister cross-canister stream


### Function `share`
``` motoko
func share() : StableData
```



### Function `unshare`
``` motoko
func unshare(d : StableData)
```

