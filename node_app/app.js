import 'dotenv/config'
import { ethers } from 'ethers'
import { Framework } from "@superfluid-finance/sdk-core"

const provider = new ethers.providers.InfuraProvider(
    "kovan",
    process.env.INFURA_API_KEY
)

console.log("provider: ", provider)

const wallet = new ethers.Wallet(
    process.env.REAL_TEST_ACCOUNT_PRIVATE_KEY,
    provider
)

console.log("wallet: ", wallet);

const superFluid = await Framework.create({
    networkName: "kovan",
    provider: provider,
});

console.log("superFluid: ", superFluid)

const signer = superFluid.createSigner({ signer: wallet });

console.log("signer transaction count: ", signer.getTransactionCount);

const DAIx = "0xe3cb950cb164a31c66e32c320a800d477019dcff"

const flowRate = "29400000000000" // The flow rate is given in wei/sec."

try {
    const createFlowOperation = superFluid.cfaV1.createFlow({
        flowRate: flowRate,
        receiver: process.env.RECIEVER_ADDRESS,
        superToken: DAIx
    })

    console.log("Creating the stream...");

    const result = await createFlowOperation.exec(signer);
    
    console.log("result: ", result);

} catch (error) {
    console.log("error:", error);
}
