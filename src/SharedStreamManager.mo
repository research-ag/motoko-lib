import Array "mo:base/Array";
import AssocList "mo:base/AssocList";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Option "mo:base/Option";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import Time "mo:base/Time";

import StreamReceiver "mo:streams/StreamReceiver";
import { StreamReceiver = Receiver } "mo:streams/StreamReceiver";
import Vec "mo:vector";

module {
  type Receiver<T> = StreamReceiver.StreamReceiver<T>;

  let TIMEOUT = 120_000_000_000;

  public type StreamSource = {
    #canister : (slotIndex : Nat, source : Principal);
    #internal;
  };

  public type StreamInfo<T> = {
    source : StreamSource;
    var length : Nat;
    var receiver : ?Receiver<T>;
  };

  type StableStreamInfo = {
    source : StreamSource;
    length : Nat;
    receiverData : ?StreamReceiver.StableData;
  };

  public type StableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, [?Nat]>);

  public func defaultStableData() : StableData = (Vec.new(), null);

  public type Callbacks<T> = {
    onReceiverRegistered : (streamId : Nat, receiver : Receiver<T>, source : StreamSource) -> ();
    onReceiverDeregistered : (streamId : Nat, receiver : Receiver<T>, source : StreamSource) -> ();
  };

  /// A manager, which is responsible for handling multiple incoming streams. Incapsulates a set of stream receivers
  public class StreamsManager<T>(
    streamsPerSourceCanister : Nat,
    itemCallback : (streamId : Nat, item : ?T, index : Nat) -> Bool,
  ) {
    public var callbacks : Callbacks<T> = {
      onReceiverRegistered = func(_) {};
      onReceiverDeregistered = func(_) {};
    };

    // info about each issued stream id is preserved here forever. Index is a stream ID
    let streams_ : Vec.Vector<StreamInfo<T>> = Vec.new();
    // a mapping of canister principal to stream id
    var sourceCanistersStreamMap : AssocList.AssocList<Principal, [?Nat]> = null;

    /// principals of registered cross-canister stream sources
    public func sourceCanisters() : [Principal] = Iter.toArray(Iter.map<(Principal, Any), Principal>(List.toIter(sourceCanistersStreamMap), func(p, n) = p));

    /// principals of cross-canister stream sources with the priority. The priority value tells the caller with what probability they should
    /// chose that canister for their needs (sum of all values is not normalized). In the future this value will be used for
    /// load balancing, for now it returns either 0 or 1. Zero value means that stream is closed and the canister should not be used
    public func prioritySourceCanisters(streamSlot : Nat) : [(Principal, Nat)] = Iter.toArray(
      Iter.map<(Principal, [?Nat]), (Principal, Nat)>(
        List.toIter(sourceCanistersStreamMap),
        func(p, n) = (
          p,
          switch (
            Option.map(
              if (streamSlot < n.size()) { n[streamSlot] } else { null },
              getStream,
            )
          ) {
            case (??stream) switch (stream.receiver) {
              case (?r) if (r.isStopped()) { 0 } else { 1 };
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
          case (#canister(_, p)) ?p;
          case (_) null;
        };
      };
    };

    private func closeStreamIfOpened(sid : Nat) = switch (Vec.getOpt(streams_, sid)) {
      case (?s) {
        switch (s.receiver) {
          case (?rec) {
            callbacks.onReceiverDeregistered(sid, rec, s.source);
            s.receiver := null;
          };
          case (_) {};
        };
      };
      case (_) {};
    };

    /// register new stream
    public func issueStreamId(source : StreamSource) : R.Result<Nat, { #NotRegistered }> {
      let id = Vec.size(streams_);
      switch (source) {
        case (#canister(slot, p)) {
          let slots : [var ?Nat] = Array.init<?Nat>(streamsPerSourceCanister, null);
          // patch with old slots
          switch (AssocList.find<Principal, [?Nat]>(sourceCanistersStreamMap, p, Principal.equal)) {
            case (null) Prim.trap("Principal " # Principal.toText(p) # " not registered as stream source");
            case (?old) {
              if (old.size() > streamsPerSourceCanister) {
                // If contained more streams before upgrade and slots amount has changed
                for (i in Iter.range(streamsPerSourceCanister, old.size() - 1)) {
                  switch (old[i]) {
                    case (?sid) closeStreamIfOpened(sid);
                    case (_) {};
                  };
                };
              };
              for (i in Iter.range(0, streamsPerSourceCanister - 1)) {
                slots[i] := if (i < old.size()) { old[i] } else { null };
              };
            };
          };
          // update stream id in slot
          switch (slots[slot]) {
            case (?oldSid) closeStreamIfOpened(oldSid);
            case (_) {};
          };
          slots[slot] := ?id;
          let (map, _) = AssocList.replace<Principal, [?Nat]>(sourceCanistersStreamMap, p, Principal.equal, ?Array.freeze(slots));
          sourceCanistersStreamMap := map;
        };
        case (#internal) {};
      };
      let rec = createReceiver(id, source);
      Vec.add(
        streams_,
        { source = source; var length = 0; var receiver = ?rec },
      );
      callbacks.onReceiverRegistered(id, rec, source);
      #ok id;
    };

    /// register new cross-canister stream
    public func registerSourceCanister(p : Principal) : () {
      switch (AssocList.find(sourceCanistersStreamMap, p, Principal.equal)) {
        case (?entry) {};
        case (_) {
          let (map, _) = AssocList.replace<Principal, [?Nat]>(
            sourceCanistersStreamMap,
            p,
            Principal.equal,
            ?Array.tabulate<?Nat>(streamsPerSourceCanister, func(n) = null),
          );
          sourceCanistersStreamMap := map;
        };
      };
    };

    /// deregister cross-canister stream
    public func deregisterSourceCanister(p : Principal) : () {
      let (map, oldValue) = AssocList.replace<Principal, [?Nat]>(sourceCanistersStreamMap, p, Principal.equal, null);
      switch (oldValue) {
        case (?streamIds) {
          sourceCanistersStreamMap := map;
          for (sidOpt in streamIds.vals()) {
            switch (sidOpt) {
              case (?sid) closeStreamIfOpened(sid);
              case (null) {};
            };
          };
        };
        case (null) {};
      };
    };

    public func share() : StableData {
      let streamsVec : Vec.Vector<StableStreamInfo> = Vec.new();
      for (info in Vec.vals(streams_)) {
        Vec.add<StableStreamInfo>(
          streamsVec,
          {
            source = info.source;
            length = info.length;
            receiverData = switch (info.receiver) {
              case (?r) {
                if (r.isStopped()) {
                  null;
                } else {
                  ?r.share();
                };
              };
              case (null) null;
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
            var length = info.length;
            var receiver = switch (info.receiverData) {
              case (?data) {
                let rec = createReceiver(id, info.source);
                rec.unshare(data);
                callbacks.onReceiverRegistered(id, rec, info.source);
                ?rec;
              };
              case (null) null;
            };
          },
        );
      };
      sourceCanistersStreamMap := d.1;
    };

    func createReceiver(streamId : Nat, source : StreamSource) : Receiver<T> = Receiver<T>(
      func(pos : Nat, item : T) {
        Vec.get(streams_, streamId).length += 1;
        itemCallback(streamId, ?item, pos);
      },
      switch (source) {
        case (#canister _) ?(TIMEOUT, Time.now);
        case (#internal) null;
      },
    );
  };

};
