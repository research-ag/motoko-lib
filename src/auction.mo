import Nat "mo:base/Nat";

type Order = (Float, Nat); // (price, volume)

let inf : Float = 1 / 0; // +inf

// Execute an auction
//
// Arguments:
// asks (= supply) must be in ascending price order
// bids (= demand) must be in descending price order
// ask price: 0.0 means a market sell order, inf not allowed
// bid price: inf means a market buy order, 0.0 not allowed
//
// Return values:
// the auction price, auction volume, number of executed asks, number of executed bids
func auction(asks : [Order], bids : [Order]) : (Float, Nat, Nat, Nat) {

  var i = 0; // number of executed ask orders (at least partially executed)
  var j = 0; // number of executed buy orders (at least partially executed)
  var ask_volume = 0;
  var bid_volume = 0;

  let res = label L : (Nat, Nat) loop {
    let orig = (i, j);
    let inc_ask = ask_volume <= bid_volume;
    let inc_bid = bid_volume <= ask_volume;
    if (inc_ask) i += 1;
    if (inc_bid) j += 1;
    if (i > asks.size() or j > bids.size()) break L orig;
    let (ask, bid) = (asks[i - 1], bids[j - 1]);
    if (ask.0 > bid.0) break L orig;
    if (inc_ask) ask_volume += ask.1;
    if (inc_bid) bid_volume += bid.1;
  };

  if (res.0 == 0) return (0.0, 0, 0, 0); // highest bid was lower than lowest ask
  // Note: i > 0 implies j > 0

  let (ask, bid) = (asks[res.0 - 1], bids[res.1 - 1]);
  let price : Float = switch (ask.0 == 0.0, bid.0 == inf) {
    case (true, true) return (0.0, 0, 0, 0); // market sell against market buy => no execution
    case (true, _) bid.0; // market sell against highest bid => use bid price
    case (_, true) ask.0; // market buy against lowest ask => use ask price
    case (_) (ask.0 + bid.0) / 2; // limit sell against limit buy => use middle price
  };

  let volume = Nat.min(ask_volume, bid_volume);

  (price, volume, res.0, res.1);
};

// Note: An ask of (0.0, _) is a market sell order. This is what the ledger uses to sell its fees.
[
  auction([], []), // => (0,0,0,0) auction failed
  auction([(0.0, 100)], [(inf, 100)]), // => (0, 0, 0, 0) auction failed
  auction([(0.0, 100)], [(inf, 100), (2.5, 100)]), // still fails because market buy absorbs all the supply
  auction([(0.0, 100)], [(inf, 99), (2.5, 100)]), // => (2.5, 100, 1, 2) all supply bought
  auction([(0.0, 100)], [(inf, 10), (2.5, 10)]), // => (2.5, 20, 1, 2) all demand filled
  auction([(0.0, 100), (1.0, 90)], [(inf, 80), (2.0, 70)]), // => (1.5, 150, 2, 2) middle price
  auction([(0.0, 100), (1.0, 90)], [(inf, 50), (2.0, 50)]), // => (2, 100, 1, 2) price is lowest bid, absorbed by market sell
  auction([(0.0, 10), (1.0, 90)], [(inf, 100), (2.0, 50)]), // => (1, 100, 2, 1) price is highest ask, absorbed by market buy
  auction([(0.0, 100), (0.5, 100), (1.0, 100), (1.5, 100)], [(inf, 100), (1.5, 50), (1.2, 100), (0.7, 100)]), // => (1.1, 250, 3, 3)
  auction([(2.0, 100)], [(1.0, 100)]), // => (0, 0, 0, 0) highest bid < lowest ask, no execution
  auction([(2.0, 100)], [(3.0, 100)]), // => (2.5, 100, 1, 1) executed at middle price
  auction([(2.0, 100)], [(inf, 100)]), // => (2, 100, 1, 1) the market order gave the buyer a better price (!)
  auction([(0.0, 100)], [(3.0, 100)]), // => (3, 100, 1, 1) the market order gave the seller a better price (!)
];

// Note: In some circumstances a market order may give a better price than a limit order.
// That is ok. The trade off is that with market orders there are no guarantees and the order book is hidden.
