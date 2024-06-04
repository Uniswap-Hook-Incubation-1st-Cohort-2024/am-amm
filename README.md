# am-amm
Paper: [AM-AMM](https://arxiv.org/abs/2403.03367)

Reference:
[Biddog](https://github.com/Bunniapp/biddog/tree/main)

Miro: [Miro board](https://miro.com/app/board/uXjVKDNc1nI=/)

# TODO

- [x] Convert topBid, nextBid just to use Epochs
- [x] function bid(epoch) epoch != getEpoch() setSwapFeeRate()
- [x] create balances[address]
- [x] function deposit
- [x] function withdraw() can't withdraw rent if the current manager
- [x] setBidPayload() -> setSwapFeeRate()
- [x] afterSwap - to redistribute the swap fee to the current manager (Lecky)
- [x] _burnBidToken() -> _chargeRent() - we charge with bidToken
- [x] Unit tests for current implementation.
- [x] beforeSwap hook to update dynamic fee
- [x] update Bid to have swapFee so that user could bid and set swapFee together
- [x] hook initialisation to set contract address for AMAMM
- [ ] Integration test to deploy AMAMM first, then deploy hook contract and initialise with AMAMM address with all the test senarios
- [ ] Record video and prepare for submission.
