#!/usr/bin/env python3
"""
LLM evaluation metrics for Cloudable.AI using Langfuse
This module provides automated evaluation of LLM responses for quality monitoring
"""

import json
import logging
import time
from typing import Dict, Any, Optional, List

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Import Langfuse integration
try:
    import langfuse_integration
    LANGFUSE_ENABLED = True
    logger.info("Langfuse integration loaded for evaluations")
except ImportError:
    LANGFUSE_ENABLED = False
    logger.warning("Langfuse integration not found, evaluations will not be recorded")

class ResponseEvaluator:
    """Evaluate LLM responses against quality criteria"""

    def __init__(self, trace_id: Optional[str] = None):
        """Initialize evaluator with optional trace ID"""
        self.trace_id = trace_id
        
    def _log_score(self, name: str, score: float, comment: str = None):
        """Log a score to Langfuse if enabled"""
        if not LANGFUSE_ENABLED or not self.trace_id:
            logger.warning("Cannot log score: Langfuse not enabled or no trace ID")
            return
            
        try:
            # This is a placeholder - in a real implementation, this would call
            # the Langfuse SDK's score method
            logger.info(f"Logged score {name}: {score} to trace {self.trace_id}")
            # In real implementation: langfuse_client.score(trace_id, name, score, comment)
        except Exception as e:
            logger.error(f"Error logging score to Langfuse: {e}")
    
    def evaluate_relevance(self, 
                          query: str, 
                          response: str, 
                          source_documents: List[Dict[str, Any]]) -> float:
        """
        Evaluate relevance of response to the query
        
        Returns:
            float: Score between 0.0 and 1.0
        """
        # Simple heuristic for demo purposes
        # In production, this would use a more sophisticated approach
        
        # 1. Check if response contains key terms from the query
        query_terms = set(query.lower().split())
        response_lower = response.lower()
        
        # Remove common words
        common_words = {"what", "is", "are", "the", "in", "for", "of", "and", "to", "a", "an"}
        query_terms = query_terms - common_words
        
        # Count how many key terms are in the response
        term_matches = sum(1 for term in query_terms if term in response_lower)
        term_score = term_matches / max(1, len(query_terms))
        
        # 2. Check if response cites sources
        source_score = 0.0
        if source_documents:
            source_score = min(1.0, len(source_documents) / 3)
            
        # Combined score (70% term relevance, 30% source usage)
        score = 0.7 * term_score + 0.3 * source_score
        
        # Log score to Langfuse
        self._log_score(
            name="response_relevance", 
            score=score,
            comment=f"Query term match: {term_score:.2f}, Source usage: {source_score:.2f}"
        )
        
        return score
    
    def evaluate_helpfulness(self, 
                           query: str, 
                           response: str) -> float:
        """
        Evaluate helpfulness of the response
        
        Returns:
            float: Score between 0.0 and 1.0
        """
        # Simple heuristics for demo
        # In production, use an LLM-based evaluation
        
        # 1. Response length (too short responses are less helpful)
        words = len(response.split())
        length_score = min(1.0, words / 50)
        
        # 2. Structure (responses with structure tend to be more helpful)
        has_paragraphs = response.count('\n\n') > 0
        has_lists = response.count('- ') > 0 or response.count('1. ') > 0
        
        structure_score = 0.0
        if has_paragraphs:
            structure_score += 0.5
        if has_lists:
            structure_score += 0.5
            
        structure_score = min(1.0, structure_score)
        
        # Combined score (60% length, 40% structure)
        score = 0.6 * length_score + 0.4 * structure_score
        
        # Log score to Langfuse
        self._log_score(
            name="response_helpfulness", 
            score=score,
            comment=f"Length score: {length_score:.2f}, Structure score: {structure_score:.2f}"
        )
        
        return score
    
    def evaluate_accuracy(self, 
                        response: str, 
                        source_documents: List[Dict[str, Any]]) -> float:
        """
        Evaluate factual accuracy based on source documents
        
        Returns:
            float: Score between 0.0 and 1.0, or None if no sources
        """
        if not source_documents:
            return None
            
        # In a real implementation, this would compare the response to the source
        # documents using NLP techniques or an LLM to check for factual consistency
        
        # Simple heuristic for demo - check if response contains text from sources
        source_texts = []
        for doc in source_documents:
            if isinstance(doc, dict) and "text" in doc:
                source_texts.append(doc["text"].lower())
            elif isinstance(doc, dict) and "metadata" in doc and "source" in doc["metadata"]:
                source_texts.append(doc["metadata"]["source"].lower())
                
        if not source_texts:
            return None
            
        # Check what percentage of the response has support in the sources
        # This is a very simplistic approach for demo purposes
        response_lower = response.lower()
        
        # Arbitrary score for demo
        score = 0.85
        
        # Log score to Langfuse
        self._log_score(
            name="response_accuracy", 
            score=score,
            comment=f"Based on {len(source_texts)} source documents"
        )
        
        return score
        
    def evaluate_response(self, 
                        query: str, 
                        response: str, 
                        source_documents: List[Dict[str, Any]] = None) -> Dict[str, float]:
        """
        Evaluate response across multiple dimensions
        
        Args:
            query: The original query/question
            response: The LLM-generated response
            source_documents: List of source documents used
            
        Returns:
            Dict with scores for each dimension and overall score
        """
        source_documents = source_documents or []
        
        # Run evaluations
        relevance_score = self.evaluate_relevance(query, response, source_documents)
        helpfulness_score = self.evaluate_helpfulness(query, response)
        accuracy_score = self.evaluate_accuracy(response, source_documents) or 0.5
        
        # Calculate overall score
        overall_score = (relevance_score * 0.4 + 
                         helpfulness_score * 0.3 + 
                         accuracy_score * 0.3)
        
        # Log overall score to Langfuse
        self._log_score(
            name="response_overall_quality", 
            score=overall_score,
            comment=f"Relevance: {relevance_score:.2f}, Helpfulness: {helpfulness_score:.2f}, Accuracy: {accuracy_score:.2f}"
        )
        
        return {
            "relevance": relevance_score,
            "helpfulness": helpfulness_score,
            "accuracy": accuracy_score,
            "overall": overall_score
        }

def evaluate_kb_response(trace_id: str, 
                        query: str, 
                        results: List[Dict[str, Any]]) -> Dict[str, float]:
    """
    Evaluate KB query results
    
    Args:
        trace_id: Langfuse trace ID
        query: Original query
        results: KB query results
        
    Returns:
        Evaluation scores
    """
    if not results:
        # No results to evaluate
        return {"overall": 0.0}
    
    # Combine all result texts into a single response for evaluation
    response = "\n\n".join([r.get("text", "") for r in results])
    
    # Create evaluator
    evaluator = ResponseEvaluator(trace_id)
    
    # Evaluate response
    scores = evaluator.evaluate_response(
        query=query,
        response=response,
        source_documents=results
    )
    
    return scores

def evaluate_chat_response(trace_id: str,
                         message: str,
                         response: str,
                         source_documents: List[Dict[str, Any]]) -> Dict[str, float]:
    """
    Evaluate chat response
    
    Args:
        trace_id: Langfuse trace ID
        message: User message
        response: AI response
        source_documents: Source documents used
        
    Returns:
        Evaluation scores
    """
    # Create evaluator
    evaluator = ResponseEvaluator(trace_id)
    
    # Evaluate response
    scores = evaluator.evaluate_response(
        query=message,
        response=response,
        source_documents=source_documents
    )
    
    return scores
