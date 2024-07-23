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

  public class Method<T>(iterations_limit : ?Nat) {
    type Response<T> = {
      var lock : Bool;
      var state : State;
      response : ?T;
    };

    let limit = Option.get(iterations_limit, 100);
    var queue : Deque.Deque<Response<T>> = Deque.empty<Response<T>>();
    var last_call_result : ?T = null;

    public func stage(arg : ?T) : ReleaseState {
      let response : Response<T> = {
        var lock = true;
        var state = #staged;
        response = arg;
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

    func run(r : Response<T>) : async* () {
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
      if (Option.isNull(r.response)) {
        throw Error.reject("");
      };
    };

    func response(r : Response<T>) : T {
      if (r.state != #ready) Debug.trap("Response not yet delivered");
      let ?x = r.response else Debug.trap("This response was a canister_rejecttrap");
      x;
    };

    public func call() : async* () {
      let ?(r, q) = Deque.popFront(queue) else Debug.trap("No response staged");
      queue := q;

      await* run(r);

      last_call_result := ?response(r);
    };

    public func call_result() : T {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func isEmpty() : Bool = Deque.isEmpty(queue);
  };
};
