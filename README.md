# Knowledge Base System: Simple Help Guide

## What This System Does

This system helps you save information from different types of files and then ask questions about that information later. It's like having your own smart assistant that remembers everything in your documents!

## Main Parts of the System

### 1. Setup Program (Setup-Environment.ps1)

This program gets everything ready for you:
- Creates folders on your computer
- Installs the AI tools you need
- Sets up your system

**How to use it:**
```
.\Setup-Environment.ps1
```

When you run this, it will ask you which drive to use. Just pick one with enough space (at least 20GB is good).

### 2. Document Processor (DocumentProcessor.ps1)

This program does the hard work:
- Watches for new files
- Reads them and understands them
- Breaks them down into smaller pieces
- Stores them so you can search them later

### 3. Question Answering System (Query-Knowledge.ps1)

This program lets you ask questions about your documents:
- Type in a question
- It finds the right information
- It gives you an answer based on your documents

**Example:**
```
> What are the main steps in the document processing workflow?

The document processing workflow involves monitoring for new files, 
extracting text from documents using appropriate processors, breaking 
the content into chunks, generating embeddings, and storing the 
processed data.

Sources:
- From: DocumentProcessor.ps1 (Similarity: 0.89)
```

### 4. Main Program with Pictures (KnowledgeBase-GUI.ps1)

This program gives you a nice window with buttons:
- Chat tab: Ask questions here
- Documents tab: See your documents and start processing

## How to Use the System

### Step 1: Set Up Your System

1. Run the setup program and follow the instructions
2. Wait for it to finish installing everything

### Step 2: Add Documents to Your System

**Using the Window with Buttons:**

1. Start the main program:
   ```
   .\KnowledgeBase-GUI.ps1
   ```

2. Click on the "Documents" tab
3. Click the "Start Document Processor" button
4. Put files in the input folder that opens
   - The system works with: PDF, Word, Excel, text files, and more

**Example:** If you have a file called "Company-Handbook.pdf", just copy it to the input folder, and the system will process it automatically.

### Step 3: Ask Questions About Your Documents

**Using the Window with Buttons:**

1. Go to the "Chat" tab
2. Type your question in the box at the bottom
3. Choose "Query Embedded Data" from the dropdown menu
4. Click "Ask" or press Enter

**Example Questions:**
- "What does our vacation policy say?"
- "Summarize the quarterly report from January"
- "What are the steps to request time off?"

**Using the Command Line:**

1. Run:
   ```
   .\Query-Knowledge.ps1
   ```
2. Type your question when asked
3. Read the answer it gives you

### Adding YouTube Videos (Optional)

If you want to add information from YouTube videos:

1. Run:
   ```
   .\Get-Transcripts.ps1
   ```
2. Type or paste a YouTube URL
3. The system will download what's being said in the video
4. It will add this information to your knowledge base

**Example:** If you found a helpful YouTube tutorial about Excel formulas, you could add it to your knowledge base by pasting the video URL. Then you could ask questions like "How do I create a VLOOKUP formula?" and get answers from that video.

## What You Need

To use this system, you need:
- A Windows computer
- Microsoft Office (for reading Word and Excel files)
- At least 20GB of free space
- Internet connection (to download the AI tools)

## Help with Common Problems

**Problem:** The document processor isn't starting.
**Solution:** Make sure you have enough disk space and try running it again.

**Problem:** The system isn't finding information from my documents.
**Solution:** Check that your documents were processed correctly. Look in the "completed" folder to see if they're there.

**Problem:** The answers don't seem right.
**Solution:** Try asking your question in a different way. Be specific about what you want to know.

## Remember!

- The system only knows about documents you've added to it
- It works best with text-based documents
- Bigger files take longer to process
- More complex questions take longer to answer

By following these steps, you can create your own smart knowledge system that helps you find information quickly!
