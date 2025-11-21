# Cloudable.AI Development Guidelines

## Code Quality Standards

### Python Code Formatting
- **Docstring Format**: Use triple-quoted strings with comprehensive descriptions for modules, classes, and functions
- **Type Annotations**: Extensive use of type hints with Union types, Optional parameters, and generic types
- **Import Organization**: Group imports by standard library, third-party packages, and local modules with clear separation
- **Line Length**: Generally follow 80-100 character line limits with logical line breaks
- **Indentation**: Consistent 4-space indentation throughout Python code

### Documentation Standards
- **Module Headers**: Include comprehensive module docstrings explaining purpose, usage, and examples
- **Function Documentation**: Detailed parameter descriptions, return types, and usage examples
- **Inline Comments**: Strategic use of comments for complex logic and business rules
- **API Documentation**: Extensive parameter documentation with type information and examples

### Error Handling Patterns
- **Exception Handling**: Comprehensive try-catch blocks with specific exception types
- **Logging Integration**: Structured logging with different levels (debug, info, warning, error)
- **Graceful Degradation**: Fallback mechanisms for API failures and missing data
- **Validation**: Input validation with clear error messages and type checking

## Structural Conventions

### File Organization
- **Modular Structure**: Clear separation of concerns with dedicated modules for different functionalities
- **Configuration Management**: Environment-based configuration with fallback defaults
- **Resource Management**: Proper cleanup and resource disposal patterns
- **Dependency Injection**: Flexible initialization with optional parameters and environment variable fallbacks

### Class Design Patterns
- **Initialization Patterns**: Comprehensive `__init__` methods with extensive parameter validation
- **Method Overloading**: Use of `@overload` decorators for type-safe method variants
- **Context Managers**: Implementation of context manager protocols for resource management
- **Property Decorators**: Strategic use of properties for computed values and validation

### Function Design
- **Parameter Handling**: Extensive use of keyword-only arguments with default values
- **Return Type Consistency**: Clear return type annotations with Union types for multiple return possibilities
- **Method Chaining**: Support for fluent interfaces where appropriate
- **Async/Sync Compatibility**: Dual support for synchronous and asynchronous operations

## Semantic Patterns

### API Integration Patterns
- **HTTP Client Management**: Centralized HTTP client configuration with timeout and retry logic
- **Authentication Handling**: Secure credential management with environment variable support
- **Response Processing**: Consistent error handling and data transformation patterns
- **Rate Limiting**: Built-in support for API rate limiting and backoff strategies

### Data Processing Patterns
- **DataFrame Operations**: Extensive use of pandas for data manipulation and analysis
- **JSON Handling**: Robust JSON serialization/deserialization with error handling
- **Data Validation**: Type checking and data validation at API boundaries
- **Caching Strategies**: Implementation of caching mechanisms for performance optimization

### Configuration Management
- **Environment Variables**: Consistent use of environment variables for configuration
- **Default Values**: Sensible defaults with override capabilities
- **Validation**: Configuration validation at startup with clear error messages
- **Dynamic Configuration**: Support for runtime configuration updates

## Internal API Usage Patterns

### AWS Service Integration
```python
# Consistent AWS service initialization
resource = boto3.client('service_name', region_name=region)

# Error handling for AWS operations
try:
    response = client.operation(parameters)
    response.raise_for_status()
except ClientError as e:
    logger.error(f"AWS operation failed: {e}")
    raise
```

### Database Operations
```python
# Parameterized queries for security
cursor.execute(
    "SELECT * FROM table WHERE column = %s",
    (parameter,)
)

# Connection management with context managers
with get_db_connection() as conn:
    # Database operations
    pass
```

### Lambda Function Patterns
```python
def lambda_handler(event, context):
    """Standard Lambda handler pattern"""
    try:
        # Extract and validate input
        body = json.loads(event.get('body', '{}'))
        
        # Process request
        result = process_request(body)
        
        # Return standardized response
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result)
        }
    except Exception as e:
        logger.exception("Lambda execution failed")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
```

## Frequently Used Code Idioms

### Conditional Initialization
```python
# Environment variable with fallback
value = os.environ.get('VARIABLE_NAME', default_value)

# Optional parameter handling
parameter = parameter or default_value
```

### List Comprehensions and Generators
```python
# Data transformation patterns
processed_items = [transform(item) for item in items if condition(item)]

# Generator expressions for memory efficiency
results = (process(item) for item in large_dataset)
```

### Dictionary Operations
```python
# Safe dictionary access
value = data.get('key', default_value)

# Dictionary comprehensions
filtered_dict = {k: v for k, v in original_dict.items() if condition(v)}
```

### String Formatting
```python
# f-string usage for readability
message = f"Processing {count} items for user {user_id}"

# Multi-line string formatting
query = """
    SELECT column1, column2
    FROM table
    WHERE condition = %s
"""
```

## Popular Annotations and Decorators

### Type Annotations
```python
from typing import Optional, Union, List, Dict, Any, Callable

def function(
    param: str,
    optional_param: Optional[int] = None,
    data: Dict[str, Any] = None
) -> Union[str, None]:
    pass
```

### Function Decorators
```python
# Retry decorator for resilience
@backoff.on_exception(backoff.expo, Exception, max_tries=3)
def api_call():
    pass

# Property decorators for computed values
@property
def computed_value(self) -> str:
    return self._compute()

# Static and class methods
@staticmethod
def utility_function():
    pass

@classmethod
def alternative_constructor(cls):
    pass
```

### Context Manager Patterns
```python
# Custom context managers
@contextmanager
def managed_resource():
    resource = acquire_resource()
    try:
        yield resource
    finally:
        release_resource(resource)
```

## Testing and Validation Patterns

### Input Validation
```python
# Parameter validation
if not isinstance(parameter, expected_type):
    raise ValueError(f"Expected {expected_type}, got {type(parameter)}")

# Range validation
if not (min_value <= value <= max_value):
    raise ValueError(f"Value must be between {min_value} and {max_value}")
```

### Logging Patterns
```python
# Structured logging
logger.info(
    "Operation completed",
    extra={
        'operation': 'process_data',
        'duration': elapsed_time,
        'items_processed': count
    }
)

# Error logging with context
logger.exception(
    "Failed to process item",
    extra={'item_id': item_id, 'user_id': user_id}
)
```

### Performance Monitoring
```python
# Timing operations
start_time = time.time()
result = expensive_operation()
duration = time.time() - start_time
logger.info(f"Operation took {duration:.2f} seconds")
```