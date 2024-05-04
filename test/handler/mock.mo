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
      if (not Option.isNull(register)) Debug.trap("staging failed. register not empty.");
      register := ?response;
      response.release;
    };
    public func clear() : async () {
      while (Option.isSome(register)) {
        await async {};
      };
    };
    public func read() : Response<T> {
      Debug.print("read");
      let ?r = register else Debug.trap("no response stage.");
      register := null;
      r;
    };
  };

};
