# am-amm
Paper: [AM-AMM](https://arxiv.org/abs/2403.03367)

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
- [x] afterSwap - to redistribute the swap fee to the current manager (Lecky)
- [ ] _burnBidToken() -> _chargeRent() - we charge with bidToken
- [ ] Unit tests for current implementation.
- [ ] beforeSwap hook to update dynamic fee
- [ ] update Bid to have swapFee so that user could bid and set swapFee together
- [ ] hook initialisation to set contract address for AMAMM
- [ ] Integration test to deploy AMAMM first, then deploy hook contract and initialise with AMAMM address with all the test senarios
- [ ] Record video and prepare for submission.
