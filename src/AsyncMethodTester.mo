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
      methods : ?(T -> S, S -> R);
    };

    let limit = Option.get(iterations_limit, 100);
    var queue : Buffer.Buffer<Response<T, S, R>> = Buffer.Buffer(1);
    var front = 0;
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> S, S -> R)) : ReleaseState {
      let response : Response<T, S, R> = {
        var lock = true;
        var state = #staged;
        methods = arg;
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
        let ?f = method else Debug.trap("Methods should be not null");
        let response : Response<T, S, R> = {
          var lock = true;
          var state = #staged;
          methods = f;
        };
        queue.add(response);
        response;
      } else {
        queue.get(front);
      };
      front += 1;

      let s = Option.apply<(T -> S, S -> R), S>(
        r.methods,
        ?(
          func((pre, _)) {
            pre(arg);
          }
        ),
      );

      r.state := #running;
      while (r.lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      r.state := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };

      let (?(_, after), ?state) = (r.methods, s) else throw Error.reject("");
      last_call_result := ?after(state);
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat) {
      let response = queue.get(i);
      if (not response.lock) {
        Debug.trap("Response must be locked before release");
      };
      response.lock := false;
    };

    public func isEmpty() : Bool = queue.size() == 0;
  };
};
