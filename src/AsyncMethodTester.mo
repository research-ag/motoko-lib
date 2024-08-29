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

  class Response<T, S, R>(method : ??(T -> S, S -> R), limit : Nat) {
    var lock = true;
    var state_ : State = #staged;
    var methods : {
      #none;
      #error;
      #some : (T -> S, S -> R);
    } = switch (method) {
      case (??x) #some(x);
      case (?null) #error;
      case (null) #none;
    };
    var result_ : ?R = null;

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
      state_ := #running;
      while (lock and inc > 0) {
        await async ();
        inc -= 1;
      };
      state_ := #ready;
      if (inc == 0) {
        Debug.trap("Iteration limit reached");
      };

      switch (methods, s) {
        case (#some(_, after), ?state) {
          result_ := ?after(state);
        };
        case (#error, _) throw Error.reject("Reject was chosen");
        case (_, _) {};
      };
    };

    public func result() : R {
      let ?r = result_ else Debug.trap("Result is not yet ready");
      r;
    };

    public func state() : State = state_;
  };

  class BaseAsyncMethodTester<T, S, R>(iterations_limit : ?Nat) {
    var queue : Buffer.Buffer<Response<T, S, R>> = Buffer.Buffer(1);
    var front = 0;
    let limit = Option.get(iterations_limit, 100);

    public func add(method : ??(T -> S, S -> R)) : Nat {
      let response = Response(method, limit);
      queue.add(response);
      queue.size() - 1;
    };

    public func popOrAdd(method : ??(T -> S, S -> R)) : Response<T, S, R> {
      let r = if (queue.size() == front) {
        let response = Response(method, limit);
        queue.add(response);
        response;
      } else {
        queue.get(front);
      };
      front += 1;
      r;
    };

    public func pop() : Response<T, S, R> {
      if (front == queue.size()) {
        Debug.trap("Pop out of empty queue");
      };
      let r = queue.get(front);
      front += 1;
      r;    
    };

    public func release(i : Nat) {
      queue.get(i).release();
    };

    public func state(i : Nat) : State {
      queue.get(i).state();
    };
  };

  public class StageAsyncMethodTester<T, S, R>(iterations_limit : ?Nat) {
    let base : BaseAsyncMethodTester<T, S, R> = BaseAsyncMethodTester<T, S, R>(iterations_limit);
    var last_call_result : ?R = null;

    public func stage(arg : ?(T -> S, S -> R)) : Nat {
      base.add(?arg);
    };

    public func call(arg : T) : async () {
      let r = base.pop();
      await r.run(arg);
      last_call_result := ?r.result();
    };

    public func call_result() : R {
      let ?r = last_call_result else Debug.trap("No call result");
      r;
    };

    public func release(i : Nat) = base.release(i);

    public func state(i : Nat) : State = base.state(i);
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
          r.result := ?after(state);
        };
        case (#error, _) throw Error.reject("Reject was chosen");
        case (_, _) {};
      };

      last_call_result := r.result;
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
