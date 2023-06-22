module {
  public module Option {

    public func guard(condition : Bool) : ?() = do ? {
      if (not condition) null!
    };
  };

  public module Num {

    public type Mod = Nat;

    type Mod_ = {
      mod : Nat -> ?Mod;
      add : (Mod, Nat) -> ?Mod;
      sub : (Mod, Nat) -> ?Mod;
    };

    public func Mod(n : Nat) : Mod_ = object {
      public func mod(x : Nat) : ?Mod = if (n == 0) null else ?(x % n);
      public func add(idx : Mod, x : Nat) : ?Mod = mod(idx + x);
      public func sub(idx : Mod, x : Nat) : ?Mod = do ? { add(idx, n - mod(x)!)! };
    };
  };
}
