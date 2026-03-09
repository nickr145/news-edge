from locust import HttpUser, between, task


class NewsEdgeUser(HttpUser):
    wait_time = between(1, 3)

    @task(3)
    def get_news(self):
        self.client.get("/api/news/NVDA")

    @task(2)
    def get_sentiment(self):
        self.client.get("/api/news/NVDA/sentiment")

    @task(1)
    def run_prediction(self):
        self.client.post("/api/predict/NVDA/sync", json={"horizon_days": 5})
