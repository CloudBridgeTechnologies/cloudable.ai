#!/usr/bin/env python3
"""
Integration script to add LLM evaluations to the Lambda function

This script modifies the lambda_function_simple.py file to add evaluation
of KB query and chat responses using the langfuse_evaluations.py module.

Run this script from the infras/core directory.
"""

import os
import re
import sys

def modify_file(file_path):
    """
    Modify the lambda function to integrate evaluations
    """
    print(f"Integrating evaluations into {file_path}")
    
    # Check if file exists
    if not os.path.exists(file_path):
        print(f"Error: File {file_path} not found")
        return False
    
    # Read file
    with open(file_path, "r") as f:
        content = f.read()
    
    # Check if already integrated
    if "import langfuse_evaluations" in content:
        print("Evaluations already integrated, skipping")
        return True
    
    # Add import
    import_pattern = r"# Import Langfuse integration\s+try:\s+import langfuse_integration"
    import_replacement = """# Import Langfuse integration
try:
    import langfuse_integration
    LANGFUSE_ENABLED = True
    logger = logging.getLogger()
    logger.info("Langfuse integration loaded successfully")
except ImportError:
    LANGFUSE_ENABLED = False
    logger = logging.getLogger()
    logger.warning("Langfuse integration not found, running without LLM observability")

# Import LLM evaluations
try:
    import langfuse_evaluations
    EVALUATIONS_ENABLED = True
    logger.info("Langfuse evaluations loaded successfully")
except ImportError:
    EVALUATIONS_ENABLED = False
    logger.warning("Langfuse evaluations not found, running without LLM quality monitoring")"""

    content = re.sub(import_pattern, import_replacement, content)
    
    # Add KB query evaluation
    kb_query_pattern = r"(# Flush observations to Langfuse\s+langfuse_integration\.flush_observations\(\)\s+\s+logger\.info\(f\"Traced KB query in Langfuse: {trace_id}\"\)\s+)(except Exception as e:\s+logger\.error\(f\"Error tracking with Langfuse: {str\(e\)}\"\))"
    kb_query_replacement = r"""\1
                    # Evaluate KB query results if evaluations are enabled
                    if EVALUATIONS_ENABLED:
                        try:
                            evaluation_scores = langfuse_evaluations.evaluate_kb_response(
                                trace_id=trace_id,
                                query=query,
                                results=results
                            )
                            logger.info(f"KB query evaluated with overall score: {evaluation_scores.get('overall', 0):.2f}")
                        except Exception as e:
                            logger.error(f"Error evaluating KB query: {str(e)}")
                    
                    \2"""
    content = re.sub(kb_query_pattern, kb_query_replacement, content)
    
    # Add chat evaluation
    chat_pattern = r"(# Flush observations to Langfuse\s+langfuse_integration\.flush_observations\(\)\s+\s+logger\.info\(f\"Traced chat interaction in Langfuse: {trace_id}\"\)\s+)(except Exception as e:\s+logger\.error\(f\"Error tracking with Langfuse: {str\(e\)}\"\))"
    chat_replacement = r"""\1
                    # Evaluate chat response if evaluations are enabled
                    if EVALUATIONS_ENABLED:
                        try:
                            evaluation_scores = langfuse_evaluations.evaluate_chat_response(
                                trace_id=trace_id,
                                message=message,
                                response=response,
                                source_documents=source_documents if use_kb else []
                            )
                            logger.info(f"Chat response evaluated with overall score: {evaluation_scores.get('overall', 0):.2f}")
                        except Exception as e:
                            logger.error(f"Error evaluating chat response: {str(e)}")
                    
                    \2"""
    content = re.sub(chat_pattern, chat_replacement, content)
    
    # Write file
    with open(file_path, "w") as f:
        f.write(content)
    
    print("Integration completed successfully")
    return True

def main():
    """
    Main function
    """
    file_path = "lambda_function_simple.py"
    
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
    
    result = modify_file(file_path)
    return 0 if result else 1

if __name__ == "__main__":
    sys.exit(main())
