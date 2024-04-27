import Error "mo:base/Error";
import Option "mo:base/Option";
import Debug "mo:base/Debug";

module {

  public type ReleaseFunc = () -> ();

  public class Response<T>(response_ : ?T) {
    var lock = true;

    public func run() : async* () {
      var inc = 100;
      while (lock and inc > 0) {
        await async {};
        inc -= 1;
      };
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
    var register : ?Response<T> = null;
    public func stage(arg : ?T) : ReleaseFunc {
      let response = Response<T>(arg);
      register := ?response;
      response.release;
    };
    public func read() : Response<T> {
      let ?r = register else Debug.trap("register not set");
      register := null;
      r;
    };
  };

};
