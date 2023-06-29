import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import R "mo:base/Result";
import AssocList "mo:base/AssocList";
import List "mo:base/List";

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

  func requireOk<T>(res : R.Result<T, Any>) : T {
    switch (res) {
      case (#ok ok) ok;
      case (_) Debug.trap("Required result is #err");
    };
  };

  public type ManagerStableData = (Vec.Vector<StableStreamInfo>, AssocList.AssocList<Principal, ?Nat>);
  public func defaultManagerStableData() : ManagerStableData = (Vec.new(), null);

  /// A manager, which is responsible for handling multiple incoming streams. Incapsulates a set of stream receivers
  public class StreamsManager<T>(
    initialSourceCanisters : [Principal],
    itemCallback : (streamId : Nat, item : T, index : Nat) -> Any,
    chunkErrorCallback : (streamId : Nat, expectedIndex : Nat, receivedIndex : Nat) -> (),
  ) {

    // info about each issued stream id is preserved here forever. Index is a stream ID
    let streams_ : Vec.Vector<StreamInfo<T>> = Vec.new();
    // a mapping of canister principal to stream id
    var sourceCanistersStreamMap : AssocList.AssocList<Principal, ?Nat> = null;

    /// principals of registered cross-canister stream sources
    public func sourceCanisters() : Vec.Vector<Principal> = Vec.fromIter(Iter.map<(Principal, ?Nat), Principal>(List.toIter(sourceCanistersStreamMap), func(p, n) = p));

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
      switch (source) {
        case (#canister p) {
          let (map, oldValue) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, ??id);
          sourceCanistersStreamMap := map;
          switch (oldValue) {
            case (??sid) Vec.get(streams_, sid).receiver := null;
            case (_) {};
          };
        };
        case (#internal) {};
      };
      Vec.add(
        streams_,
        {
          source = source;
          var nextItemId = 0;
          var receiver = ?SharedStream.StreamReceiver<T>(id, 0, 120, streamItemCallback, func(e, r) = chunkErrorCallback(id, e, r));
        },
      );
      #ok id;
    };

    func streamItemCallback(streamId : Nat, item : T, index : Nat) {
      let stream = Vec.get(streams_, streamId);
      stream.nextItemId += 1;
      ignore itemCallback(streamId, item, index);
    };

    /// register new internal stream
    public func issueInternalStreamId() : Nat = requireOk(issueStreamId(#internal));

    /// register new cross-canister stream
    public func registerSourceCanister(p : Principal) : () {
      switch (AssocList.find(sourceCanistersStreamMap, p, Principal.equal)) {
        case (?entry) {};
        case (_) {
          let (map, _) = AssocList.replace<Principal, ?Nat>(sourceCanistersStreamMap, p, Principal.equal, null);
          sourceCanistersStreamMap := map;
        };
      };
    };

    /// handle chunk from incoming request
    public func processBatch(source : Principal, streamId : Nat, batch : [T], firstIndex : Nat) : R.Result<(), SharedStream.ResponseError> {
      let stream = Vec.get(streams_, streamId);
      let callerOk = switch (stream.source) {
        case (#canister p) Principal.equal(source, p);
        case (#internal) false;
      };
      if (not callerOk) {
        return #err(#NotRegistered);
      };
      switch (stream.receiver) {
        case (?receiver) receiver.onChunk(batch, firstIndex);
        case (null) #err(#NotRegistered);
      };
    };

    /// append item to internal stream
    public func pushInternalItem(streamId : Nat, item : T) : (Nat, Nat) {
      let stream = Vec.get(streams_, streamId);
      switch (stream.source) {
        case (#canister p) Debug.trap("Cannot internally produce item in #canister stream");
        case (#internal) {};
      };
      switch (stream.receiver) {
        case (null) Debug.trap("Internal stream has to have an active receiver");
        case (?receiver) {
          let id = stream.nextItemId;
          requireOk(receiver.onChunk([item], id));
          (streamId, id);
        };
      };
    };

    public func share() : ManagerStableData {
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

    public func unshare(d : ManagerStableData) {
      for ((info, id) in Vec.items(d.0)) {
        Vec.add(
          streams_,
          {
            source = info.source;
            var nextItemId = info.nextItemId;
            var receiver = switch (info.active) {
              case (true) ?SharedStream.StreamReceiver<T>(id, info.nextItemId, 120, streamItemCallback, func(e, r) = chunkErrorCallback(id, e, r));
              case (false) null;
            };
          },
        );
      };
      sourceCanistersStreamMap := d.1;
    };
  };

};
