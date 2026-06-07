import pymysql
import os
from dotenv import load_dotenv

load_dotenv()

host = os.getenv("DB_HOST", "localhost")
user = os.getenv("DB_USER", "root")
password = os.getenv("DB_PASS", "")
db_name = os.getenv("DB_NAME", "loan_analyzer")

def setup():
    try:
        # Connect without DB first
        conn = pymysql.connect(host=host, user=user, password=password)
        cursor = conn.cursor()
        
        # Create DB
        cursor.execute(f"CREATE DATABASE IF NOT EXISTS {db_name}")
        conn.select_db(db_name)
        print(f"[SUCCESS] Database '{db_name}' ready.")
        
        # Create Tables if not exist
        # We'll just let the FastAPI app do create_all, but we can seed users here
        # For simplicity, we just print instructions and add them via SQL if they match our User model
    except Exception as e:
        print(f"[ERROR] Could not connect to MySQL: {e}")
        print("Please make sure MySQL is running (XAMPP/WAMP/Service).")

if __name__ == "__main__":
    setup()
