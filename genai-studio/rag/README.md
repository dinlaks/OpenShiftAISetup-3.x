# GenAI Studio RAG Guide

## Overview

**GenAI Studio** is an interactive environment within Red Hat OpenShift AI (RHOAI) for prototyping and evaluating generative AI models. It enables prompt testing, model comparison, and RAG (Retrieval-Augmented Generation) workflow evaluation.

**Status:** Technology Preview in RHOAI 3.0 (unsupported)

**Note:** This is a stateless environment. Chat history and settings are lost on browser refresh or session end.

## Prerequisites

> To use the MCP Weather server via GenAI Studio, you must first deploy the required model by following the instructions in [deploy-model.md](/deploy-model.md).

- Configured playground instance for your project
- Llama Stack Operator enabled (set `managementState: Managed` in DataScienceCluster CR)
- Supported file formats: PDF, DOC, CSV
- Upload limits: 10 files max, 10MB per file
- RAG uses inline vector database only (no external database support)

## Quick Start: Enable RAG

1. Access the Playground in the OpenShift AI dashboard
2. Toggle RAG on and expand the section
3. Click **Upload** and select documents from your system
4. Ask questions about your uploaded documents
5. The model retrieves relevant information to answer

## Sample RAG Demo 

1. Use the [sample file](test_story.pdf) provided in this repo for RAG testing using GenAI Studio Playground.
2. Toggle RAG on and expand the section 
3. Click **Upload** and select documents from your system

Now, lets ask a question based on uploaded documents. 

```bash
summarise the test_story?

who is the main character in this test_story?
```

## Advanced Configuration

| Setting | Purpose | Recommendation |
|---------|---------|-----------------|
| **Max chunk length** | Word count per text section | Smaller for precision, larger for context |
| **Chunk overlap** | Repeated words between chunks | Improves response quality via context continuity |
| **Delimiter** | Text chunk boundary (e.g., `.` or `\n`) | Choose based on document structure |
