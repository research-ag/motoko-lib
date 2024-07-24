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

  public class AsyncMethodTester<T, R>(iterations_limit : ?Nat) {
    type Response<T, R> = {
      var lock : Bool;
      var state : State;
      method : ?(T -> R);
    };

    let limit = Option.get(iterations_limit, 100);
    var queue : Deque.Deque<Response<T, R>> = Deque.empty<Response<T, R>>();
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> R)) : ReleaseState {
      let response : Response<T, R> = {
        var lock = true;
        var state = #staged;
        method = arg;
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

    func await_unlock(r : Response<T, R>) : async* () {
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

    public func call(arg : T) : async* () {
      let ?(r, q) = Deque.popFront(queue) else Debug.trap("No response staged");
      queue := q;

      await* await_unlock(r);

      if (Option.isNull(r.method)) {
        throw Error.reject("");
      };
      let ?method = r.method else throw Error.reject("");
      last_call_result := ?method(arg);
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func isEmpty() : Bool = Deque.isEmpty(queue);
  };
};
