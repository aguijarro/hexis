import logging
from fastapi import FastAPI, HTTPException, UploadFile, File, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Dict
import uvicorn
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
from langchain_chroma import Chroma
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.prompts import ChatPromptTemplate, HumanMessagePromptTemplate
from langchain.schema.runnable import RunnablePassthrough, RunnableLambda
from langchain.schema.output_parser import StrOutputParser
from langchain.schema import SystemMessage
from langchain.memory import ConversationBufferMemory
import networkx as nx
import matplotlib.pyplot as plt
import io
import json
import os
from dotenv import load_dotenv
from fastapi.responses import StreamingResponse
from functools import lru_cache

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

class Question(BaseModel):
    query: str
    conversation_id: str

class SystemsAnalysis(BaseModel):
    elements: List[str]
    relationships: List[Dict[str, str]]
    query: str

class Settings:
    def __init__(self):
        self.openai_api_key = os.getenv("OPENAI_API_KEY")
        if not self.openai_api_key:
            raise ValueError("OPENAI_API_KEY environment variable is not set")

@lru_cache()
def get_settings():
    return Settings()

# Initialize LangChain components with dependency injection
def get_embeddings(settings: Settings = Depends(get_settings)):
    return OpenAIEmbeddings(openai_api_key=settings.openai_api_key)

def get_vector_store(embeddings: OpenAIEmbeddings = Depends(get_embeddings)):
    return Chroma(embedding_function=embeddings, persist_directory="./chroma_db")

def get_llm(settings: Settings = Depends(get_settings)):
    return ChatOpenAI(
        temperature=0.7,
        openai_api_key=settings.openai_api_key
    )

# Consolidated template
ANALYSIS_TEMPLATE = """
Analyze the following business question or context using a systems thinking approach:

Question/Context: {question_or_context}

Consider the following aspects:
1. Identify key elements and their relationships
2. Analyze feedback loops and causality
3. Consider short-term and long-term implications
4. Identify leverage points for intervention

Provide a structured analysis with clear recommendations.

Analysis:
"""


def get_qa_chain(
    vector_store: Chroma = Depends(get_vector_store),
    settings: Settings = Depends(get_settings)
):
    llm = ChatOpenAI(
        temperature=0,
        openai_api_key=settings.openai_api_key,
        model_name="gpt-3.5-turbo"
    )
    
    prompt = ChatPromptTemplate.from_messages([
        SystemMessage(content="You are a systems thinking expert."),
        HumanMessagePromptTemplate.from_template(ANALYSIS_TEMPLATE)
    ])
    
    retriever = vector_store.as_retriever()
    
    def _retrieve_docs(input_dict):
        return retriever.get_relevant_documents(input_dict["question_or_context"])

    chain = (
        {
            "context": RunnableLambda(_retrieve_docs),
            "chat_history": lambda x: "\n".join(x["chat_history"]),
            "question_or_context": lambda x: x["question_or_context"]
        }
        | prompt
        | llm
        | StrOutputParser()
    )
    
    return chain

class Conversation(BaseModel):
    id: str
    messages: List[Dict[str, str]]

conversations = {}

@app.options("/analyze")
async def analyze_options():
    return {"message": "OK"}

@app.post("/start_conversation")
async def start_conversation():
    conversation_id = str(len(conversations) + 1)
    conversations[conversation_id] = Conversation(id=conversation_id, messages=[])
    return {"conversation_id": conversation_id}

@app.post("/analyze")
async def analyze_question(
    question: Question,
    qa_chain = Depends(get_qa_chain)
):
    try:
        logger.info(f"Received question: {question.query}")
        logger.info(f"Conversation ID: {question.conversation_id}")
        
        if question.conversation_id not in conversations:
            logger.info(f"Creating new conversation with ID: {question.conversation_id}")
            conversations[question.conversation_id] = Conversation(id=question.conversation_id, messages=[])
        
        conversation = conversations[question.conversation_id]
        
        conversation.messages.append({"role": "user", "content": question.query})
        
        result = qa_chain.invoke({
            "question_or_context": question.query,  # Changed from "question" to "question_or_context"
            "chat_history": [f"{m['role']}: {m['content']}" for m in conversation.messages[:-1]]
        })
        
        conversation.messages.append({"role": "assistant", "content": result})
        
        logger.info("Analysis completed successfully")
        return {"analysis": result, "conversation": conversation.messages}
    except Exception as e:
        logger.error(f"Error in analyze_question: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload-document")
# Todo: Improve to not save data when the file is the same
async def upload_document(
    file: UploadFile = File(...),
    vector_store: Chroma = Depends(get_vector_store)
):
    try:
        logger.info(f"Uploading document: {file.filename}")
        content = await file.read()
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200
        )
        texts = text_splitter.split_text(content.decode())
        vector_store.add_texts(texts)
        logger.info("Document processed successfully")
        return {"message": "Document processed successfully"}
    except Exception as e:
        logger.error(f"Error in upload_document: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.route("/systems-map", methods=["POST", "GET"])
async def create_systems_map(request: Request):
    try:
        logger.info("Creating systems map")
        
        # If it's a GET request, use some default data
        if request.method == "GET":
            elements = ["Element 1", "Element 2", "Element 3"]
            relationships = [
                {"source": "Element 1", "target": "Element 2", "type": "influences"},
                {"source": "Element 2", "target": "Element 3", "type": "affects"}
            ]
        else:
            # For POST requests, parse the JSON body
            body = await request.json()
            elements = body.get("elements", [])
            relationships = body.get("relationships", [])
        
        G = nx.DiGraph()
        
        for element in elements:
            G.add_node(element)
        
        for relationship in relationships:
            G.add_edge(
                relationship["source"],
                relationship["target"],
                label=relationship.get("type", "influences")
            )
        
        plt.figure(figsize=(12, 8))
        pos = nx.spring_layout(G)
        nx.draw(G, pos, with_labels=True, node_color='lightblue', 
                node_size=2000, font_size=8, font_weight='bold')
        
        img_bytes = io.BytesIO()
        plt.savefig(img_bytes, format='png')
        img_bytes.seek(0)
        
        logger.info("Systems map created successfully")
        return StreamingResponse(img_bytes, media_type="image/png")
    except Exception as e:
        logger.error(f"Error in create_systems_map: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
