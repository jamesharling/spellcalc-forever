interface IConfig
{
    // Rule set the generator applies. World of Warcraft: Forever uses classic-era rules, so the
    // existing "CLASSIC" code paths are kept; "WOTLK" paths are legacy and unused in this fork.
    expansion: "CLASSIC" | "WOTLK",
    dataDir: string,
    outputDir: string,
}

const cfg: IConfig = {
    expansion: "CLASSIC",
    dataDir: "data/forever/",
    outputDir: __dirname + "/../../../data/forever/"
}

export { cfg }