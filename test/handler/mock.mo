import Debug "mo:base/Debug";
import Deque "mo:base/Deque";
import Error "mo:base/Error";
import Option "mo:base/Option";

module {
  let iteration_limit = 100;

  public type ReleaseFunc = () -> ();

  public class Response<T>(response_ : ?T) {
    var lock = true;

    public func run() : async* () {
      var inc = iteration_limit;
      while (lock and inc > 0) {
        await async {};
        inc -= 1;
      };
      if (inc == 0) Debug.trap("iteration limit reached.");
      if (Option.isNull(response_)) throw Error.reject("");
    };

    public func response() : T {
      let ?x = response_ else Debug.trap("wrong use. always call run before response.");
      x;
    };

    public func release() {
      assert lock;
      lock := false;
    };
  };

  public class Method<T>() {
    var queue : Deque.Deque<Response<T>> = Deque.empty<Response<T>>();
    public func stage(arg : ?T) : ReleaseFunc {
      let response = Response<T>(arg);
      queue := Deque.pushBack(queue, response);
      response.release;
    };
    public func pop() : Response<T> {
      let ?(r, q) = Deque.popFront(queue) else Debug.trap("no response staged.");
      queue := q;
      r;
    };
  };

};
