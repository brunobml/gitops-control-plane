# Welcome to the Lab Pilot

Thank you for trying two short labs on a GitOps platform. **We are testing the documents, not you.** Every place where you get stuck is a mistake in the documents that we want to find and fix.

## What you will do
| Session | Document | Time | What you learn |
|---|---|---|---|
| A | [Lab 0: Tour the Running Lab](../lab-0-guided-tour.md) | about 60 min | how one application travels from Git to (mock) AWS, through Argo CD, kro and ACK; what a tenant may and may not do; watch two controllers repair things |
| B | [Lab 1: Write a Blueprint](../lab-1-write-a-blueprint.md) | about 60–90 min | write your own kro blueprint in a throwaway cluster, watch it fail on purpose, and fix it |

The lab is already running. The required Lab 0 actions are read-only or designed to be repaired by a controller; one step briefly deletes a mock cloud queue while ACK recreates it. Lab 1 runs in its own throwaway cluster. If a command fails or a resource does not come back, stop and tell the facilitator.

## How to work
* **Copy and paste the commands**, in order, into one terminal. You do not need to type YAML.
* **Say out loud** what you expect before you run a block, and what surprised you afterwards. This is the most useful thing you can give us.
* **Predict, then look.** Each station asks a question first. Guess before you run the commands; being wrong is how you learn here.
* **Answer the "Check yourself" questions before you open the answers**, and say your answer aloud or write it down. Lab 0 has five, at station 8; Lab 1 has four, at the end.
* **Skip** Lab 0's "Optional: the Git side": it changes a shared repository.
* **Ask** whenever you want. The facilitator will mostly stay quiet and take notes. If you are stuck for 5 minutes, they will give you a small hint.

## What you need to know already
`kubectl` basics (contexts, namespaces, `get`, `logs`, `describe`), and what a Kubernetes controller is. Argo CD, kro, ACK and moto are explained in the labs; terms are in [Concepts, Glossary & Self-Check](../concepts-and-glossary.md).

## Privacy
You are recorded as a code (`P1`, `P2`, …), never by name. Your notes and the facilitator's notes stay off the repository; only anonymous numbers and the problems you found are published. At the end, five short survey questions.
