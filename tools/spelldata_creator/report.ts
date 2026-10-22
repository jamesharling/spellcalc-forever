import * as fs from "fs";
import { cfg, getBuildInfo } from "./config";

/**
 * Collects everything the generator skipped, guessed or wants a human to check.
 * Written to cfg.reportFile at the end of a run so the result can be reviewed
 * without scrolling through the console output.
 */

const sections = new Map<string, string[]>();
let currentSection = "General";

export function reportSection(name: string)
{
    currentSection = name;
    if (!sections.has(name)) sections.set(name, []);
}

export function report(message: string)
{
    if (!sections.has(currentSection)) sections.set(currentSection, []);
    const list = sections.get(currentSection)!;
    if (list.indexOf(message) !== -1) return;
    list.push(message);
    console.log("REPORT: " + message);
}

export function writeReport()
{
    const build = getBuildInfo();
    let text = `SpellCalc Forever data generation report\n`;
    text += `Client build: ${build.product} ${build.version}\n`;
    text += `Generated: ${new Date().toISOString()}\n\n`;
    text += `Everything listed here was skipped or guessed by the generator and should be reviewed.\n\n`;

    for (const [name, list] of sections)
    {
        text += `== ${name} (${list.length})\n`;
        for (const line of list) text += `  ${line}\n`;
        text += "\n";
    }

    fs.writeFileSync(cfg.reportFile, text);
    console.log("Report written to " + cfg.reportFile);
}
