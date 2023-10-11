import AssocList "mo:base/AssocList";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import R "mo:base/Result";

import Vec "mo:vector";
import SharedStream "SharedStream";

module {

  public type StreamSource = { #canister : Principal; #internal };

  public type StreamInfo<T> = {
    source : StreamSource;
    var nextItemId : Nat;
    var receiver : ?SharedStream.StreamReceiver<T>;
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
          switch (Option.flatten(Option.map(n, getStream))) {
            case (?stream) switch (stream.receiver) {
              case (?r) if (r.isStreamClosed()) { 0 } else { 1 };
              case (null) 0;
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
          case (#canister p) ?p;
          case (_) null;
        };
      };
    };

    /// register new stream
    public func issueStreamId(source : StreamSource) : R.Result<Nat, { #NotRegistered }> {
      let id = Vec.size(streams_);
      var closeStreamTimeoutSeconds : ?Nat = ?120;
      switch (source) {
        case (#canister p) {
          let (map, oldValue) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, ??id);
          sourceCanistersStreamMap := map;
          switch (oldValue) {
            case (??sid) Vec.get(streams_, sid).receiver := null;
            case (?null) {};
            case (null) Debug.trap("Principal " # Principal.toText(p) # " not registered as stream source");
          };
        };
        case (#internal) {
          closeStreamTimeoutSeconds := null;
        };
      };
      Vec.add(
        streams_,
        {
          source = source;
          var nextItemId = 0;
          var receiver = ?SharedStream.StreamReceiver<T>(id, 0, closeStreamTimeoutSeconds, streamItemCallback);
        },
      );
      #ok id;
    };

    func streamItemCallback(streamId : Nat, item : ?T, index : Nat) {
      let stream = Vec.get(streams_, streamId);
      stream.nextItemId += 1;
      ignore itemCallback(streamId, item, index);
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
        case (?x) sourceCanistersStreamMap := map;
        case (null) {};
      };
    };

    public func share() : StableData {
      let streamsVec : Vec.Vector<StableStreamInfo> = Vec.new();
      for (info in Vec.vals(streams_)) {
        Vec.add(
          streamsVec,
          {
            source = info.source;
            nextItemId = info.nextItemId;
            active = switch (info.receiver) {
              case (?r) true;
              case (null) false;
            };
          },
        );
      };
      (streamsVec, sourceCanistersStreamMap);
    };

    public func unshare(d : StableData) {
      Vec.clear(streams_);
      for ((info, id) in Vec.items(d.0)) {
        Vec.add(
          streams_,
          {
            source = info.source;
            var nextItemId = info.nextItemId;
            var receiver = switch (info.active) {
              case (true) ?SharedStream.StreamReceiver<T>(
                id,
                info.nextItemId,
                switch (info.source) {
                  case (#canister _) ?120;
                  case (#internal) null;
                },
                streamItemCallback,
              );
              case (false) null;
            };
          },
        );
      };
      sourceCanistersStreamMap := d.1;
    };
  };

};
