package adminauth

import (
 "context"
 "errors"
 "testing"
)

func TestCreateUserRejectsWeakCredentialsBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil)
 _,err:=service.CreateUser(context.Background(),User{ID:"actor"},"ab","","short")
 if !errors.Is(err,ErrInvalidInput){t.Fatalf("expected ErrInvalidInput, got %v",err)}
}

func TestNonSuperAdminCannotGrantAdminManagementPermission(t *testing.T) {
 service:=NewService(nil)
 err:=service.SetPermissions(context.Background(),User{ID:"operator"},"target",[]string{"admin_users.manage"})
 if !errors.Is(err,ErrForbidden){t.Fatalf("expected ErrForbidden, got %v",err)}
}

func TestSetPermissionsRejectsOversizedPermissionList(t *testing.T) {
 service:=NewService(nil)
 permissions:=make([]string,65)
 err:=service.SetPermissions(context.Background(),User{ID:"root",IsSuperAdmin:true},"target",permissions)
 if !errors.Is(err,ErrInvalidInput){t.Fatalf("expected ErrInvalidInput, got %v",err)}
}

func TestNewTokenReturnsOpaqueTokenAndExpiry(t *testing.T) {
 token,hash,expires,err:=newToken(0)
 if err!=nil{t.Fatal(err)}
 if token==""||len(hash)!=32{t.Fatal("expected opaque token and SHA-256 hash")}
 if expires.IsZero(){t.Fatal("expected expiry timestamp")}
}

func TestSetUserStatusRejectsInvalidStateBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil)
 err:=service.SetUserStatus(context.Background(),User{ID:"actor"},"target","pending")
 if !errors.Is(err,ErrInvalidInput){t.Fatalf("expected ErrInvalidInput, got %v",err)}
}

func TestSetUserStatusPreventsSelfDisableBeforeDatabaseAccess(t *testing.T) {
 service:=NewService(nil)
 err:=service.SetUserStatus(context.Background(),User{ID:"same-user"},"same-user","disabled")
 if !errors.Is(err,ErrForbidden){t.Fatalf("expected ErrForbidden, got %v",err)}
}
