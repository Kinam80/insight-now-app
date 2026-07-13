import google.generativeai as genai

# 형님의 API 키를 여기에 넣으세요
API_KEY = "형님의_GEMINI_API_KEY"

def test_api_connection():
    try:
        genai.configure(api_key="AIzaSyDUEPVkUDFXL1vBQh27c0w61_huIu4W6L8")
        
        # 1. 사용 가능한 모델 리스트 출력 (권한 확인)
        print("--- 사용 가능한 모델 리스트 ---")
        for m in genai.list_models():
            if 'generateContent' in m.supported_generation_methods:
                print(f"모델 이름: {m.name}")
        
        # 2. 간단한 응답 테스트 (연결 확인)
        model = genai.GenerativeModel('models/gemini-3.5-flash')
        response = model.generate_content("안녕, 지금 API 연결 테스트 중이야. 짧게 응답해줘.")
        
        print("\n--- 연결 테스트 결과 ---")
        print(f"응답 내용: {response.text}")
        print("\n성공: API 키가 정상적으로 작동합니다!")
        
    except Exception as e:
        print(f"\n에러 발생: {e}")
        print("API 키가 잘못되었거나 네트워크 문제일 수 있습니다. 다시 확인해주세요.")

if __name__ == "__main__":
    test_api_connection()