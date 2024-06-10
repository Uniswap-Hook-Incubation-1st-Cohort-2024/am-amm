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
- [x] user firstly needs to add liquidity to obtain the pool token, then can use it as rent to bid
- [x] "The current highest bidder in the ongoing auction, known as the manager, pays rent to liquidity providers." - need to send rent from AMAMM back to LP
- [x] Integration test to deploy AMAMM first, then deploy hook contract and initialise with AMAMM address with all the test scenarios
- [x] Record the video and prepare it for submission.

Integration test scenarios:
- As a user, I should be able to bid an epoch to be a manager so that I can collect all fees as expecting high volume
- As a user, I should be able to bid an epoch to be a manager so that I can set a high swap fee that I would be the only arbitrageur
