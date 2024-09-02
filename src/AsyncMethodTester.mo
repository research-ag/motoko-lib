import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Option "mo:base/Option";
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

  class Response<T, S, R>(method : ??(T -> S, S -> R), limit : Nat) {
    var lock = true;
    public var state : State = #staged;
    public var methods : {
      #none;
      #error;
      #some : (T -> S, S -> R);
    } = switch (method) {
      case (??x) #some(x);
      case (?null) #error;
      case (null) #none;
    };
    public var result : ?R = null;

    public func release() {
      if (not lock) {
        Debug.trap("Response must be locked before release");
      };
      lock := false;
    };

    public func run(arg : T) : async () {
      let s = switch (methods) {
        case (#some(pre, _)) ?pre(arg);
        case (_) null;
      };

      var inc = limit;
      state := #running;
      while (lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      state := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };

      switch (methods, s) {
        case (#some(_, after), ?state) {
          result := ?after(state);
        };
        case (#error, _) throw Error.reject("Reject was chosen");
        case (_, _) {};
      };
    };
  };

  class BaseAsyncMethodTester<T, S, R>(iterations_limit : ?Nat) {
    var queue : Buffer.Buffer<Response<T, S, R>> = Buffer.Buffer(1);
    var front = 0;
    let limit = Option.get(iterations_limit, 100);

    public func add(method : ??(T -> S, S -> R)) : Nat {
      let response = Response<T, S, R>(method, limit);
      queue.add(response);
      queue.size() - 1;
    };

    public func pop() : ?Response<T, S, R> {
      if (front == queue.size()) {
        return null;
      };
      let r = queue.get(front);
      front += 1;
      ?r;
    };

    public func get(i : Nat) : Response<T, S, R> = queue.get(i);
  };

  public class StageAsyncMethodTester<T, S, R>(iterations_limit : ?Nat) {
    let base : BaseAsyncMethodTester<T, S, R> = BaseAsyncMethodTester<T, S, R>(iterations_limit);
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> S, S -> R)) : Nat {
      base.add(?arg);
    };

    public func call(arg : T) : async () {
      let ?r = base.pop() else Debug.trap("Pop out of empty queue");
      await r.run(arg);
      last_call_result := r.result;
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat) = base.get(i).release();

    public func state(i : Nat) : State = base.get(i).state;
  };

  public class CallAsyncMethodTester<S, R>(iterations_limit : ?Nat) {
    let base : BaseAsyncMethodTester<S, S, R> = BaseAsyncMethodTester<S, S, R>(iterations_limit);
    var last_call_result : ?R = null;

    public func call(arg : S, method : ?(S -> R)) : async () {
      let m = ?Option.map<S -> R, (S -> S, S -> R)>(
        method,
        func(m) = (func(x) = x, m),
      );
      let r = base.get(base.add(m));
      await r.run(arg);
      last_call_result := r.result;
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat) = base.get(i).release();

    public func state(i : Nat) : State = base.get(i).state;
  };

  public class ReleaseAsyncMethodTester<R>(iterations_limit : ?Nat) {
    let base : BaseAsyncMethodTester<(), (), R> = BaseAsyncMethodTester<(), (), R>(iterations_limit);
    var last_call_result : ?R = null;

    public func call() : async () {
      let r = base.get(base.add(null));
      await r.run(());
      last_call_result := r.result;
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat, result : ?R) {
      let response = base.get(i);

      assert Option.isNull(response.result);

      response.release();
      
      switch (result) {
        case (?r) {
          response.result := ?r;
        };
        case (null) {
          response.methods := #error;
        };
      };
    };

    public func state(i : Nat) : State = base.get(i).state;
  };
};
