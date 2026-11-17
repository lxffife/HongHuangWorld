#include "persistence/durable_outbox.hpp"
#include <cassert>
#include <cstdio>
#include <string>
int main() {
    const std::string path="world_outbox_test.sqlite";
    std::remove(path.c_str()); std::remove((path+"-wal").c_str()); std::remove((path+"-shm").c_str());
    {
        honghuang::persistence::DurableOutbox box(path,2); std::string error;
        assert(box.enqueue({"e1","character_reward","{""xp"":20}",0,100,100,{}},error));
        assert(box.enqueue({"e1","character_reward","{""xp"":20}",0,100,100,{}},error));
        assert(box.pending_count(error)==1);
        auto first=box.claim_due(100,error); assert(first && first->event_id=="e1");
        assert(!box.claim_due(100,error));
    }
    {
        honghuang::persistence::DurableOutbox box(path,2); std::string error;
        auto recovered=box.claim_due(100,error); assert(recovered && recovered->attempts==0);
        assert(box.schedule_retry("e1",1,250,"temporary failure",error));
        assert(!box.claim_due(200,error));
        auto retry=box.claim_due(250,error); assert(retry && retry->attempts==1);
        assert(box.mark_delivered("e1",error)); assert(box.pending_count(error)==0);
        assert(box.enqueue({"e2","ground_drop_create","{""item"":""wolf_fang""}",0,0,300,{}},error));
        assert(box.enqueue({"e3","ground_drop_create","{""item"":""wolf_pelt""}",0,0,301,{}},error));
        assert(!box.enqueue({"e4","ground_drop_create","{""item"":""other""}",0,0,302,{}},error));
    }
    std::remove(path.c_str()); std::remove((path+"-wal").c_str()); std::remove((path+"-shm").c_str());
}
