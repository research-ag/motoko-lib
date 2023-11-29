import AssocList "mo:base/AssocList";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Option "mo:base/Option";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import Time "mo:base/Time";

import StreamSender "mo:streams/StreamSender";
import StreamReceiver "mo:streams/StreamReceiver";
import Vec "mo:vector";

module {

  let TIMEOUT = 120_000_000_000;

  public type StreamSource = { #canister : Principal; #internal };

  public type StreamInfo<T> = {
    var source : {
      #canister : (Principal, ?StreamReceiver.StreamReceiver<T>);
      #internal : ?InternalStreamReceiver<T>;
    };
    var nextItemId : Nat;
  };

  type StableStreamInfo = {
    source : StreamSource;
    nextItemId : Nat;
    active : Bool;
  };

  public type StableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, ?Nat>);
  public func defaultStableData() : StableData = (Vec.new(), null);

  func assocListFromIter<K, V>(iter : Iter.Iter<(K, V)>, equal : (K, K) -> Bool) : AssocList.AssocList<K, V> {
    var l : AssocList.AssocList<K, V> = null;
    for ((k, v) in iter) {
      let (upd, _) = AssocList.replace<K, V>(l, k, equal, ?v);
      l := upd;
    };
    l;
  };

  public class InternalStreamReceiver<T>(
    startPos : Nat,
    itemCallback : (pos : Nat, item : T) -> (),
  ) {

    var length_ : Nat = startPos;

    public func length() : Nat = length_;

    public func insertItem(it : T) : Nat {
      itemCallback(length_, it);
      length_ += 1;
      length_ - 1;
    };
  };

  /// A manager, which is responsible for handling multiple incoming streams. Incapsulates a set of stream receivers
  public class StreamsManager<T>(
    initialSourceCanisters : [Principal],
    itemCallback : (streamId : Nat, item : ?T, index : Nat) -> Any,
  ) {

    // info about each issued stream id is preserved here forever. Index is a stream ID
    let streams_ : Vec.Vector<StreamInfo<T>> = Vec.new();
    // a mapping of canister principal to stream id
    var sourceCanistersStreamMap : AssocList.AssocList<Principal, ?Nat> = assocListFromIter(
      Iter.map<Principal, (Principal, ?Nat)>(
        Iter.fromArray(initialSourceCanisters),
        func(p) = (p, null),
      ),
      Principal.equal,
    );

    /// principals of registered cross-canister stream sources
    public func sourceCanisters() : [Principal] = Iter.toArray(Iter.map<(Principal, ?Nat), Principal>(List.toIter(sourceCanistersStreamMap), func(p, n) = p));

    /// principals and id-s of registered cross-canister stream sources
    public func canisterStreams() : [(Principal, ?Nat)] = Iter.toArray(List.toIter(sourceCanistersStreamMap));

    /// principals of cross-canister stream sources with the priority. The priority value tells the caller with what probability they should
    /// chose that canister for their needs (sum of all values is not normalized). In the future this value will be used for
    /// load balancing, for now it returns either 0 or 1. Zero value means that stream is closed and the canister should not be used
    public func prioritySourceCanisters() : [(Principal, Nat)] = Iter.toArray(
      Iter.map<(Principal, ?Nat), (Principal, Nat)>(
        List.toIter(sourceCanistersStreamMap),
        func(p, n) = (
          p,
          switch (Option.map(n, getStream)) {
            case (??stream) switch (stream.source) {
              case (#canister(_, receiver)) switch (receiver) {
                case (?r) if (r.hasTimedOut()) { 0 } else { 1 };
                case (null) 0;
              };
              case (_) 0;
            };
            case (_) 0;
          },
        ),
      )
    );

    /// get stream info by id
    public func getStream(id : Nat) : ?StreamInfo<T> = Vec.getOpt(streams_, id);

    /// get id, which will be assigned to next registered stream
    public func getNextStreamId() : Nat = Vec.size(streams_);

    /// get principal of stream source by stream id
    public func sourceCanisterPrincipal(streamId : Nat) : ?Principal {
      switch (Vec.getOpt(streams_, streamId)) {
        case (null) null;
        case (?info) switch (info.source) {
          case (#canister(p, _)) ?p;
          case (_) null;
        };
      };
    };

    func clearReceiver(streamId : Nat) : () {
      let info = Vec.get(streams_, streamId);
      switch (info.source) {
        case (#canister(p, _)) info.source := #canister(p, null);
        case (#internal _) info.source := #internal(null);
      };
    };

    func streamItemCallback(streamId : Nat, item : T, index : Nat) {
      let stream = Vec.get(streams_, streamId);
      stream.nextItemId += 1;
      ignore itemCallback(streamId, ?item, index);
    };

    /// register new stream
    public func issueStreamId(source : StreamSource) : R.Result<Nat, { #NotRegistered }> {
      let id = Vec.size(streams_);
      let cb = func(pos : Nat, item : T) = streamItemCallback(id, item, pos);
      switch (source) {
        case (#canister p) {
          let (map, oldValue) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, ??id);
          sourceCanistersStreamMap := map;
          switch (oldValue) {
            case (??sid) clearReceiver(sid);
            case (?null) {};
            case (null) Prim.trap("Principal " # Principal.toText(p) # " not registered as stream source");
          };
          Vec.add<StreamInfo<T>>(
            streams_,
            {
              var source = #canister(p, ?StreamReceiver.StreamReceiver<T>(0, ?(TIMEOUT, Time.now), cb));
              var nextItemId = 0;
            },
          );
        };
        case (#internal) {
          Vec.add<StreamInfo<T>>(
            streams_,
            {
              var source = #internal(?InternalStreamReceiver(0, cb));
              var nextItemId = 0;
            },
          );
        };
      };
      #ok id;
    };

    /// register new cross-canister stream
    public func registerSourceCanister(p : Principal) : () {
      switch (AssocList.find(sourceCanistersStreamMap, p, Principal.equal)) {
        case (?entry) {};
        case (_) {
          let (map, _) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, ?null);
          sourceCanistersStreamMap := map;
        };
      };
    };

    /// deregister cross-canister stream
    public func deregisterSourceCanister(p : Principal) : () {
      let (map, oldValue) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, null);
      switch (oldValue) {
        case (?streamIdOpt) {
          sourceCanistersStreamMap := map;
          switch (streamIdOpt) {
            case (?streamId) clearReceiver(streamId);
            case (null) {};
          };
        };
        case (null) {};
      };
    };

    public func share() : StableData {
      let streamsVec : Vec.Vector<StableStreamInfo> = Vec.new();
      for (info in Vec.vals(streams_)) {
        Vec.add(
          streamsVec,
          switch (info.source) {
            case (#canister(p, r))({
              source = #canister(p);
              nextItemId = info.nextItemId;
              active = switch (r) {
                case (?rec) not rec.hasTimedOut();
                case (null) false;
              };
            });
            case (#internal r)({
              source = #internal;
              nextItemId = info.nextItemId;
              active = not Option.isNull(r);
            });
          },
        );
      };
      (streamsVec, sourceCanistersStreamMap);
    };

    public func unshare(d : StableData) {
      Vec.clear(streams_);
      for ((info, id) in Vec.items(d.0)) {
        let cb = func(pos : Nat, item : T) = streamItemCallback(id, item, pos);
        Vec.add(
          streams_,
          {
            var source = switch (info.source) {
              case (#canister p) #canister(
                p,
                switch (info.active) {
                  case (true) ?StreamReceiver.StreamReceiver<T>(info.nextItemId, ?(TIMEOUT, Time.now), cb);
                  case (false) null;
                },
              );
              case (#internal) #internal(
                switch (info.active) {
                  case (true) ?InternalStreamReceiver<T>(info.nextItemId, cb);
                  case (false) null;
                }
              );
            };
            var nextItemId = info.nextItemId;
          },
        );
      };
      sourceCanistersStreamMap := d.1;
    };
  };

};
