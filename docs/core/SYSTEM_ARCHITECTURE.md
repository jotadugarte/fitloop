# System Architecture & Boundaries

**Purpose:** This document defines the unchangeable technical laws of the project. AI agents are strictly forbidden from proposing or implementing solutions that violate these boundaries unless an explicit Architectural Decision Record (ADR) is approved.

## 1. The Technology Stack
* **Language/Runtime:** [e.g., TypeScript 5.x / Ruby 3.x]
* **Core Framework:** [e.g., Expo React Native / Ruby on Rails 8]
* **Primary Database:** [e.g., SQLite via Drizzle ORM / PostgreSQL]
* **Styling/UI Engine:** [e.g., Tamagui / CSS Variables & BEM]

## 2. Architectural Paradigm
* **Design Pattern:** [e.g., Local-First Offline Sync / Service-Object Backend]
* **State Management:** [e.g., React Query for Server State, Zustand for UI State]
* **API Paradigm:** [e.g., RESTful JSON / GraphQL]

## 3. The "Kill List" (Forbidden Patterns)
*AI Agents MUST NOT use or suggest the following under any circumstances:*
* 🚫 **[Forbidden Tech 1]:** [e.g., Tailwind CSS - Use Tamagui tokens instead]
* 🚫 **[Forbidden Tech 2]:** [e.g., Redux - Use React Query]
* 🚫 **[Forbidden Pattern]:** [e.g., Fat Controllers - All business logic must be in Service Objects]

## 4. Environment & Infrastructure
* **Deployment Target:** [e.g., iOS/Android App Stores / Kamal to Bare Metal]
* **Secrets Management:** [e.g., Expo SecureStore / Rails Credentials]
