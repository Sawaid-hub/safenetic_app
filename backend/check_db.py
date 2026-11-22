import os

import firebase_admin
from firebase_admin import firestore

firebase_admin.initialize_app()
db = firestore.client()

user_id = os.environ.get('SAFENETIC_DIAGNOSTIC_UID')
if not user_id:
    raise SystemExit('Set SAFENETIC_DIAGNOSTIC_UID to the account to inspect.')

guardian_tokens_ref = db.collection('users').document(user_id).collection('guardian_tokens')
docs = guardian_tokens_ref.stream()

print(f'Guardian device count: {sum(1 for _ in docs)}')
