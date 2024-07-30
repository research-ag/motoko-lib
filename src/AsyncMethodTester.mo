import Debug "mo:base/Debug";
import Deque "mo:base/Deque";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Bool "mo:base/Bool";

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
    var queue : Deque.Deque<Response<T, S, R>> = Deque.empty<Response<T, S, R>>();
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> S, S -> R)) : ReleaseState {
      let response : Response<T, S, R> = {
        var lock = true;
        var state = #staged;
        methods = arg;
      };

      queue := Deque.pushBack(queue, response);

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

    public func call(arg : T) : async* () {
      var inc = limit;
      while (Deque.isEmpty(queue)) {
        await async ();
        inc -= 1;
      };

      let ?(r, q) = Deque.popFront(queue) else Debug.trap("No response staged");
      queue := q;

      r.state := #running;
      let s = Option.apply<(T -> S, S -> R), S>(
        r.methods,
        ?(
          func((pre, _)) {
            pre(arg);
          }
        ),
      );
      while (r.lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      r.state := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };

      let ?(_, after)= r.methods else throw Error.reject("");
      last_call_result := ?(after(Option.unwrap(s)));
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func isEmpty() : Bool = Deque.isEmpty(queue);
  };
};
