# am-amm
[AM-AMM](https://arxiv.org/abs/2403.03367)

Reference:
[Biddog](https://github.com/Bunniapp/biddog/tree/main)

Miro: [Miro board](https://miro.com/app/board/uXjVKDNc1nI=/)

# TODO

- [ ] Convert topBid, nextBid just to use Epochs
- [ ] function bid(epoch) epoch != getEpoch() setSwapFeeRate()
- [ ] function cancel(epoch) epoch != getEpoch()
- [ ] create balances[address]
- [ ] function deposit
- [ ] function withdraw() can't withdraw rent if the current manager
- [ ] setBidPayload() -> setSwapFeeRate()
- [ ] NoOp - to redistribute the swap fee to the current manager
- [ ] _burnBidToken() -> _chargeRent() - we charge with bidToken

