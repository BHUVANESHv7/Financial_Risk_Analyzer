from sqlalchemy.orm import Session
from database import SessionLocal, User, init_db
from auth import get_password_hash

def seed_final():
    print("[INIT] Creating tables if missing...")
    init_db()
    
    db = SessionLocal()
    try:
        users_to_add = [
            ("admin@risk.com", "admin123", "ADMIN"),
            ("applicant@risk.com", "password123", "APPLICANT")
        ]
        
        for email, pwd, role in users_to_add:
            # Check if user already exists
            existing = db.query(User).filter(User.email == email).first()
            if existing:
                print(f"[SEED] User {email} already exists, updating password.")
                existing.hashed_password = get_password_hash(pwd)
                existing.role = role
            else:
                print(f"[SEED] Creating new user: {email}")
                new_user = User(
                    email=email,
                    hashed_password=get_password_hash(pwd),
                    role=role
                )
                db.add(new_user)
        
        db.commit()
        print("[SUCCESS] Users seeded successfully.")
    except Exception as e:
        print(f"[ERROR] Seeding failed: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    seed_final()
