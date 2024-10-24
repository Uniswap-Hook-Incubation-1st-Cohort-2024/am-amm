# am-amm

Entry: [Uniswap Hook Incubator Hackathon](https://uniswap.atrium.academy/hackathons/hookathon-c1/projects/ae6965c8-8e5d-43f1-b74e-6bf63f2455d9/)

Paper: [AM-AMM](https://arxiv.org/abs/2403.03367)

Biddog: [Biddog](https://github.com/Bunniapp/biddog/tree/main)

Miro: [Miro board](https://miro.com/app/board/uXjVKDNc1nI=/)

Slides: [Gamma slides](https://gamma.app/docs/Introduction-to-Auction-Managed-Automated-Market-Makers-am-AMMs--3t88pi5q43qzgs6?mode=doc)

Presentation Video: [Loom video](https://www.loom.com/share/e713c20906cb4656af67b2797d200fb1)

X: https://x.com/AtriumAcademy/status/1803882301396521222

# Flows

<img width="1275" alt="image" src="https://github.com/Uniswap-Hook-Incubation-1st-Cohort-2024/am-amm/assets/148800/f830e3fe-101f-4792-a5e9-baafdb62ef71">

# Tests

<img width="642" alt="Screenshot 2024-06-10 at 5 13 54 PM" src="https://github.com/Uniswap-Hook-Incubation-1st-Cohort-2024/am-amm/assets/47234753/1fca5708-84e9-4789-8ac6-92873d40ab88">

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
