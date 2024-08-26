import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Bool "mo:base/Bool";
import Buffer "mo:base/Buffer";

module {
  public type State = {
    #staged;
    #running;
    #ready;
  };

  public type ReleaseState = {
    release : () -> ();
    state : () -> State;
  };

  public class AsyncMethodTester<T, S, R>(iterations_limit : ?Nat) {
    type Response<T, S, R> = {
      var lock : Bool;
      var state : State;
      var methods : {
        #none;
        #error;
        #some : (T -> S, S -> R);
      };
      var result : ?R;
    };

    let limit = Option.get(iterations_limit, 100);
    var queue : Buffer.Buffer<Response<T, S, R>> = Buffer.Buffer(1);
    var front = 0;
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> S, S -> R)) : ReleaseState {
      let response : Response<T, S, R> = {
        var lock = true;
        var state = #staged;
        var methods = switch (arg) {
          case (?x) #some(x);
          case (null) #error;
        };
        var result = null;
      };

      queue.add(response);

      object {
        public func release() {
          if (not response.lock) {
            Debug.trap("Response must be locked before release");
          };
          response.lock := false;
        };

        public func state() : State = response.state;
      };
    };

    public func call(arg : T, method : ??(T -> S, S -> R)) : async* () {
      var inc = limit;
      let r = if (queue.size() == front) {
        let response : Response<T, S, R> = {
          var lock = true;
          var state = #staged;
          var methods = switch (method) {
            case (??x) #some(x);
            case (?null) #error;
            case (null) #none;
          };
          var result = null;
        };
        queue.add(response);
        response;
      } else {
        queue.get(front);
      };
      front += 1;

      let s = switch (r.methods) {
        case (#some(pre, _)) ?pre(arg);
        case (_) null;
      };

      r.state := #running;
      while (r.lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      r.state := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };

      switch (r.methods, s) {
        case (#some(_, after), ?state) {
          last_call_result := ?after(state);
          r.result := last_call_result;
        };
        case (#error, _) throw Error.reject("Reject was chosen");
        case (_, _) {};
      };
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat, result : ??R) {
      let response = queue.get(i);
      if (not response.lock) {
        Debug.trap("Response must be locked before release");
      };
      if (not Option.isNull(result) and not Option.isNull(response.result)) {
        Debug.trap("Results can't be simultaneously present");
      };

      response.lock := false;
      if (Option.isNull(response.result)) {
        switch (result) {
          case (??r) {
            response.result := ?r;
          };
          case (?null) {
            response.methods := #error;
          };
          case (_) {};
        };
      };
    };

    public func isEmpty() : Bool = queue.size() == 0;
  };
};
