#!/usr/bin/env zx

function getPackageNames() {
    const packagesPath = path.join(__dirname, "../packages")
    const packageNames = []
    for (const folderName of fs.readdirSync(packagesPath)) {
        if (folderName !== "common") {
            packageNames.push(folderName)
        }
    }
    return packageNames
}

// NOTE: the version will look like year.month.day-timestamp
function getVersion() {
    const now = new Date()
    const fullYear = now.getUTCFullYear()
    const month = now.getUTCMonth() + 1
    const day = now.getUTCDate()
    const timestamp = now.getTime()

    return `${fullYear}.${month}.${day}-${timestamp}`
}

function createPackageJsonForPublish() {
    const packageJson = require("../package.json")
    const packageJsonForPublish = {
        name: "@perp/lugia-deployments",
        version: getVersion(),
        description: "Perpetual Protocol Lugia contract artifacts (ABIs) and deployed addresses",
        license: packageJson.license,
        author: packageJson.author,
        repository: packageJson.repository,
        homepage: packageJson.homepage,
        keywords: packageJson.keywords,
    }
    fs.writeFileSync(`output/package.json`, JSON.stringify(packageJsonForPublish, null, 2))
}

void (async function pack() {
    await $`rm -rf output/`
    await $`mkdir -p output/`
    await $`cp README.md output/`

    const packageNames = getPackageNames()
    for (const packageName of packageNames) {
        await $`mkdir -p output/${packageName}/`

        // uncomment when we need it
        // await $`cp -r contracts/ output/${packageName}/contracts`

        await $`mkdir -p output/${packageName}/artifacts/`
        await $`cp -r packages/${packageName}/artifacts/lib/ output/${packageName}/artifacts/lib/`
        await $`cp -r packages/${packageName}/artifacts/src/ output/${packageName}/artifacts/src/`
        await $`find output/${packageName}/artifacts/ -name "*.dbg.json" -type f -delete`

        await $`cp -r packages/${packageName}/metadata/${packageName}.json output/${packageName}/metadata.json`
    }

    createPackageJsonForPublish()
})()
