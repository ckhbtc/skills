---
name: blog-writer
description: Write product announcement blog posts and technical articles. Focuses on "how it works + how to get started" style, not "we're alive and well" announcements. Use when the user says "write a blog post", "write an announcement", or "create a post about".
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Blog Writer Skill

## Overview

Write compelling product announcement blog posts for DeFi/crypto products. The tone is technical but accessible -- show what the product does, how it works under the hood, and how to get started.

## Style Guide

### Tone
- **Technical but approachable** -- assume the reader is a developer or trader, not a normie
- **Show, don't tell** -- code snippets, architecture diagrams, concrete examples
- **No fluff** -- skip "we're excited to announce" or "we're thrilled". Just say what it is
- **Direct** -- lead with what the product does in the first sentence
- **Confident** -- no hedging ("we think", "we believe"). State facts

### Structure
1. **Title**: Short, punchy, describes what the thing does (not who made it)
2. **Opening paragraph**: What is it? What problem does it solve? One paragraph max
3. **How it works**: Technical deep-dive. Architecture, protocols, signing flows. Include diagrams if helpful
4. **Getting started**: Step-by-step. Code snippets, CLI commands, config examples
5. **What's next**: Brief roadmap teaser. 2-3 sentences max

### Formatting
- Use headers (H2, H3) liberally
- Code blocks with language tags
- Keep paragraphs short (3-4 sentences max)
- Use bullet points for lists of features/steps
- Bold key terms on first use

### Length
- Standard post: 800-1200 words
- Deep-dive: 1500-2500 words
- Quick announcement: 300-500 words

## Context

The user works in the Injective blockchain ecosystem, building:
- TrueCurrent Exchange (perpetual futures DEX)
- EasyPerps (trading frontend)
- DexPal (market data API)
- Hummingbot connector
- x402 payment gateway
- NinjaBattle (AI bot trading competition)
- RFQ protocol for derivatives

Posts often target: developers integrating with Injective, traders looking for new platforms, market makers evaluating opportunities.

## Process

1. Read the relevant code/docs to understand the product deeply
2. Draft the post following the structure above
3. Include real code snippets from the actual codebase (not made-up examples)
4. Ask user for review before finalizing
5. Output as markdown file
