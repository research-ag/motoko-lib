import Debug "mo:base/Debug";
import Deque "mo:base/Deque";
import Error "mo:base/Error";
import Option "mo:base/Option";

module {
  let iteration_limit = 100;

  public type State = { #staged; #running; #ready };
  public type ReleaseFunc = () -> ();
  public type StateFunc = () -> State;

  public class Response<T>(response_ : ?T) {
    var lock_ = true;
    var state_ : State = #staged;

    public func run() : async* () {
      state_ := #running;
      var inc = iteration_limit;
      while (lock_ and inc > 0) {
        await async {};
        inc -= 1;
      };
      state_ := #ready;
      if (inc == 0) Debug.trap("iteration limit reached.");
      if (Option.isNull(response_)) throw Error.reject("");
    };

    public func response() : T {
      if (state_ != #ready) Debug.trap("response not yet delivered.");
      let ?x = response_ else Debug.trap("this response was a canister_rejecttrap.");
      x;
    };

    public func release() {
      assert lock_;
      lock_ := false;
    };

    public func state() : State = state_;
    public func lock() : Bool = lock_;
  };

  public class Method<T>() {
    var queue : Deque.Deque<Response<T>> = Deque.empty<Response<T>>();
    public func stage(arg : ?T) : (ReleaseFunc, StateFunc) {
      let response = Response<T>(arg);
      queue := Deque.pushBack(queue, response);
      (response.release, response.state);
    };
    public func pop() : Response<T> {
      let ?(r, q) = Deque.popFront(queue) else Debug.trap("no response staged.");
      queue := q;
      r;
    };
    public func isEmpty() : Bool = Deque.isEmpty(queue);
  };

};
