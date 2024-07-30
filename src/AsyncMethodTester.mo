import Debug "mo:base/Debug";
import Deque "mo:base/Deque";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";
import Result "mo:base/Result";

module {
  public type State = {
    #empty;
    #response_arrived;
    #request_arrived;
    #running;
    #ready;
  };

  public type ReleaseState = {
    release : () -> ();
    state : () -> State;
  };

  public class AsyncMethodTester<TReq, TState, TResp>(
    before : TReq -> TState,
    after : TState -> TResp,
    iterations_limit : ?Nat,
  ) {
    type Request<T> = {
      #error;
      #arg : T;
    };

    func requsetToData(r : Request<TReq>) : Data<TReq, TState, TResp> {
      let #arg x = r else return #error;
      #before x;
    };

    type Data<TReq, TState, TResp> = {
      #error;
      #before : TReq;
      #middle : TState;
      #after : TResp;
    };

    type Call<TReq, TState, TResp> = {
      var lock : Bool;
      var state : State;
      var data : ?Data<TReq, TState, TResp>;
    };

    func new<TReq, TResp>() : Call<TReq, TState, TResp> = {
      var lock = true;
      var state = #empty;
      var data = null;
    };

    let limit = Option.get(iterations_limit, 100);
    var calls : Buffer.Buffer<Call<TReq, TState, TResp>> = Buffer.Buffer<Call<TReq, TState, TResp>>(2);
    var resp_count = 0;
    var req_count = 0;
    var last_call_result : ?TResp = null;

    public func stage(arg : Request<TReq>) : Nat {
      if (calls.size() == resp_count) {
        calls.add(new());
      };

      let call = calls.get(resp_count);
      if (not Option.isNull(call.data)) {
        Debug.trap("Data must be null before stage");
      };
      call.data := ?requsetToData(arg);

      let ret = resp_count;
      resp_count += 1;

      ret;
    };

    public func release(index : Nat) {
      let call = calls.get(index);
      if (not call.lock) {
        Debug.trap("Call must be locked before release");
      };
      call.lock := false;
    };

    public func state(index : Nat) : State = calls.get(index).state;

    func await_unlock(r : Call<TReq, TState, TResp>) : async* () {
      r.state := #running;
      var inc = limit;
      while (r.lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      r.state := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };
    };

    public func call(arg : ?Request<TReq>) : async* () {
      if (calls.size() == req_count) {
        calls.add(new());
      };

      let call = calls.get(resp_count);
      switch (arg) {
        case (?r) {
          if (not Option.isNull(call.data)) {
            Debug.trap("Data must be null before call");
          };
          call.data := ?requsetToData(r);
        };
        case _ {};
      };

      Option.iterate(call.data, func (d) {
        let #before r = d else assert false;
        call.data := 
      });

      await* await_unlock(call);

      if (Option.isNull(r.method)) {
        throw Error.reject("");
      };
      let ?method = r.method else throw Error.reject("");
      last_call_result := ?method(arg);
    };

    public func call_result() : TResp {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func isEmpty() : Bool = Deque.isEmpty(queue);
  };
};
