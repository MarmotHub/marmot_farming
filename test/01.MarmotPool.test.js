const hre = require('hardhat')
const { expect } = require('chai')
const BigNumber = require("bignumber.js");

const fs = require("fs");
const file = fs.createWriteStream("../deploy-logger.js", { 'flags': 'w'});
let logger = new console.Console(file, file);

const decimalStr = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 18).toFixed(0, BigNumber.ROUND_DOWN)
}

const decimalStrUSDT = (value) => {
  return new BigNumber(value).multipliedBy(10 ** 6).toFixed(0, BigNumber.ROUND_DOWN)
}
// rescale
function one(value=1, left=0, right=18) {
    let from = ethers.BigNumber.from('1' + '0'.repeat(left))
    let to = ethers.BigNumber.from('1' + '0'.repeat(right))
    return ethers.BigNumber.from(value).mul(to).div(from)
}

function neg(value) {
    return value.mul(-1)
}



const MAX = ethers.BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

describe('MarmotPool', function () {

    let deployer
    let alice
    let bob

    let usdt
    let btc
    let eth
    let bnb
    let marmot

    let oracleUSDTUSD
    let oracleBTCUSD
    let oracleETHUSD
    // let oracleETHUSD

    let pool

    beforeEach(async function() {
        [deployer, alice, bob] = await ethers.getSigners()
        deployer.name = 'deployer'
        alice.name = 'alice'
        bob.name = 'bob'

        usdt = await (await ethers.getContractFactory('TERC20')).deploy('Test USDT', 'USDT', 6)
        btc = await (await ethers.getContractFactory('TERC20')).deploy('Test BTC', 'BTC', 18)
        eth = await (await ethers.getContractFactory('TERC20')).deploy('Test ETH', 'ETH', 18)
        bnb = await (await ethers.getContractFactory('TERC20')).deploy('Test BNB', 'BNB', 18)
        marmot = await (await ethers.getContractFactory('MarmotToken')).deploy()

        pool = await (await ethers.getContractFactory('MarmotPool')).deploy(
            marmot.address,
            decimalStr("40"),
            decimalStr("60"),
            100
        )

        console.log("pool deployed")

        for (account of [deployer, alice, bob]) {
            await usdt.mint(account.address, decimalStrUSDT(10000))
            await usdt.connect(account).approve(pool.address, MAX)
            await btc.mint(account.address, decimalStr(1))
            await btc.connect(account).approve(pool.address, MAX)
        }

        await marmot.addMinter(pool.address)
        await marmot.transferOwnership(pool.address)

        console.log("transfer ownership")

        //
        oracleUSDTUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        oracleBTCUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        oracleETHUSD = await (await ethers.getContractFactory('NaiveOracle')).deploy()
        await oracleUSDTUSD.setPrice(decimalStr(1))
        await oracleBTCUSD.setPrice(decimalStr(40000))
        await oracleETHUSD.setPrice(decimalStr(3000))


        await pool.addPool(
            usdt.address,
            'usdt',
            decimalStr(1),
            ZERO_ADDRESS
            )
        await pool.addPool(
            btc.address,
            'btc',
            decimalStr("0.8"),
            oracleBTCUSD.address
            )
        await pool.addPool(
            eth.address,
            'eth',
            decimalStr("0.5"),
            oracleETHUSD.address
            )
        await pool.addPool(
            bnb.address,
            'bnb',
            decimalStr("0.5"),
            oracleETHUSD.address
            )
    })

    it('addLiquidity/removeLiquidity work correctly', async function () {
        console.log('start')
        console.log(await pool.getPoolLength());
        //
        await pool.connect(deployer).deposit(0, decimalStr("10000"))
        await pool.connect(alice).deposit(1, decimalStr("1"))

        // console.log('pool0', await pool.getPoolInfo(0))
        // console.log('pool1', await pool.getPoolInfo(1))
        // console.log("user0", await pool.getUserInfo(0,deployer.address))
        // console.log("user1", await pool.getUserInfo(1,bob.address))

        await pool.connect(deployer).claimAll()
        console.log("deployer marmot balance", await marmot.balanceOf(deployer.address))
        await pool.connect(alice).claimAll()
        console.log("alice marmot balance", await marmot.balanceOf(alice.address))

        console.log("deployer balance", (await usdt.balanceOf(deployer.address)).toString())
        console.log("deployer balance", (await marmot.balanceOf(deployer.address)).toString())
        await pool.connect(deployer).withdraw(0, decimalStr(10000))
        console.log("deployer balance", (await usdt.balanceOf(deployer.address)).toString())
        console.log("deployer balance", (await marmot.balanceOf(deployer.address)).toString())

        console.log("alice balance", (await btc.balanceOf(alice.address)).toString())
        console.log("alice balance", (await marmot.balanceOf(alice.address)).toString())
        // await pool.connect(alice).emergencyWithdraw(1)
        console.log("alice balance", (await btc.balanceOf(alice.address)).toString())
        console.log("alice balance", (await marmot.balanceOf(alice.address)).toString())

        // await pool.connect(alice).withdraw(1, decimalStr("1"))
        console.log("alice marmot balance", await marmot.balanceOf(alice.address))

        console.log('alice pending', await pool.pending(1, alice.address))
        console.log('alice pendingAll', await pool.connect(alice).pendingAll())
        await new Promise(resolve => setTimeout(resolve, 10000))
        console.log('alice pendingAll', await pool.connect(alice).pendingAll())


        // await addLiquidity(deployer, decimalStr(10000), false)
        // await addLiquidity(alice, decimalStr(50000), false)
        //
        // await expect(removeLiquidity(deployer, decimalStr(20000), false)).to.be.revertedWith('LToken: burn amount exceeds balance')
        // await removeLiquidity(alice, decimalStr(50000), false)
        // await removeLiquidity(deployer, decimalStr(1000), false)

    })


})
